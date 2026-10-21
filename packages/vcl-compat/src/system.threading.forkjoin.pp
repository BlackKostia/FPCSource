{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 2026 by the Free Pascal development team

    Groups of fine-grained tasks on work-stealing deques

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{ See docs/concurrency/adr/0013-forkjoin-fine-grained-tasks.md.

  A task is a record without managed fields, kept by value in the deque of
  the thread that spawned it. Status, the first exception and cancellation
  belong to the group, not to a task. Idle threads steal from the other
  deques; a thread that waits for a group runs tasks itself. }
unit System.Threading.ForkJoin;

interface

{$mode objfpc}
{$h+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}

uses
{$IFDEF FPC_DOTTEDUNITS}
  System.SysUtils, System.Classes, System.Threading;
{$ELSE}
  SysUtils, Classes, System.Threading;
{$ENDIF}

type
  // A task with an argument: the argument is passed by value, so a loop can
  // spawn one lambda without capturing its loop variable
  TArgProc = reference to procedure(aArg: Int64);
  // A task without a closure: no reference counting at all
  TPlainProc = procedure(aData: Pointer);

  { TTaskGroup }

  TTaskGroup = class
  private
    FPending: Int64;
    FException: Pointer;
    FCancelled: LongBool;
    FCancelledByError: LongBool;
    procedure SetException(aObject: TObject);
    procedure WaitForTasks;
  public
    constructor Create;
    // Waits for the tasks of the group; an exception of a task is freed
    destructor Destroy; override;
    procedure Spawn(const aProc: TProcRef); overload;
    procedure Spawn(aArg: Int64; const aProc: TArgProc); overload;
    procedure Spawn(aProc: TPlainProc; aData: Pointer); overload;
    // Runs tasks until the group is done, then re-raises the first exception
    // of a task. An exception cancels the tasks of the group that have not
    // started; after Wait the group can be used again.
    procedure Wait;
    // Tasks of the group that have not started yet are skipped
    procedure Cancel;
    function IsCancelled: Boolean;
  end;

  { TForkJoin }

  TForkJoin = class sealed
  public
    // Calls aProc for every index in [aLow..aHigh], splitting the range in
    // halves down to aGrain indices (0: range / (8 * threads))
    class procedure Each(aLow, aHigh: Int64; const aProc: TArgProc; aGrain: Int64 = 0); static;
    // Runs aFirst in the calling thread and aSecond in parallel
    class procedure Join(const aFirst, aSecond: TProcRef); static;
    // Worker threads of the pool; a thread waiting in Wait runs tasks as well
    class function WorkerCount: Integer; static;
  end;

implementation

const
  CDequeSize = 4096;
  CDequeMask = CDequeSize - 1;
  CMaxDeques = 256;
  CMaxParked = 512;
  CSpinRounds = 64;

type
  TTaskKind = (tkRef, tkArg, tkPlain, tkRange);

  // No managed fields: copied by value, without RTTI or reference counting.
  // Code is the closure (an interface, one reference held by the task) or a
  // plain procedure.
  TTask = record
    Group: TTaskGroup;
    Code: Pointer;
    A, B, C: Int64;
    Kind: TTaskKind;
  end;

  // Chase-Lev deque: the owner pushes and pops at Bottom, thieves take at Top
  PDeque = ^TDeque;
  TDeque = record
    Top: Int64;
    Pad1: array[0..6] of Int64;
    Bottom: Int64;
    Pad2: array[0..6] of Int64;
    Items: array[0..CDequeSize - 1] of TTask;
  end;

  TParkEntry = record
    Key: Pointer;      // the group waited for, or nil for an idle worker
    Event: PRTLEvent;
  end;

  TPool = class;

  TWorker = class(TThread)
  private
    FPool: TPool;
    FDeque: PDeque;
  protected
    procedure Execute; override;
  public
    constructor Create(aPool: TPool; aDeque: PDeque);
  end;

  { TPool }

  TPool = class
  private
    FDeques: array[0..CMaxDeques - 1] of PDeque;
    FDequeCount: LongInt;
    FWorkers: array of TWorker;
    FStop: LongBool;
    FParkLock: TRTLCriticalSection;
    FParked: array[0..CMaxParked - 1] of TParkEntry;
    FParkedCount: LongInt;
    FIdleWorkers: LongInt;
    FWakeToken: LongInt;
    function NewDeque: PDeque;
    function TryPark(aKey: Pointer; aEvent: PRTLEvent): Boolean;
    procedure Unpark(aEvent: PRTLEvent);
  public
    constructor Create;
    destructor Destroy; override;
    function CurrentDeque: PDeque;
    function TrySteal(aSelf: PDeque; out aTask: TTask): Boolean;
    function FindTask(aOwn: PDeque; out aTask: TTask): Boolean;
    // Called after a push: wakes one idle worker if any sleeps
    procedure Notify;
    procedure WakeGroupWaiters(aGroup: Pointer);
    procedure ParkWorker(aDeque: PDeque);
    procedure ParkWaiter(aGroup: TTaskGroup);
  end;

var
  GPool: TPool = nil;
  GPoolLock: TRTLCriticalSection;

threadvar
  tvDeque: PDeque;
  tvNoDeque: Boolean;
  tvParkEvent: PRTLEvent;
  tvRandom: LongWord;

function Pool: TPool;

begin
  Result := GPool;
  if Result <> nil then
    Exit;
  EnterCriticalSection(GPoolLock);
  try
    if GPool = nil then
      GPool := TPool.Create;
    Result := GPool;
  finally
    LeaveCriticalSection(GPoolLock);
  end;
end;

procedure CpuRelax;

begin
{$IF defined(CPUX86_64) or defined(CPUI386)}
  asm
    pause
  end;
{$ENDIF}
end;

function NextRandom: LongWord;

var
  X: LongWord;

begin
  X := tvRandom;
  if X = 0 then
    X := LongWord(PtrUInt(@tvRandom)) or 1;
  // xorshift32
  X := X xor (X shl 13);
  X := X xor (X shr 17);
  X := X xor (X shl 5);
  tvRandom := X;
  Result := X;
end;

function ParkEvent: PRTLEvent;

begin
  Result := tvParkEvent;
  if Result = nil then
    begin
    Result := RTLEventCreate;
    tvParkEvent := Result;
    end;
end;

{ Deque }

function DequePush(aDeque: PDeque; const aTask: TTask): Boolean;

var
  B, T: Int64;

begin
  B := aDeque^.Bottom;
  T := Volatile(aDeque^.Top);
  if B - T >= CDequeSize then
    Exit(False);
  aDeque^.Items[B and CDequeMask] := aTask;
  // Stores are not reordered with stores on x86; elsewhere publish the item
  // before the new bottom
{$IF not (defined(CPUX86_64) or defined(CPUI386))}
  WriteBarrier;
{$ENDIF}
  Volatile(aDeque^.Bottom) := B + 1;
  Result := True;
end;

function DequePop(aDeque: PDeque; out aTask: TTask): Boolean;

var
  B, T: Int64;

begin
  B := aDeque^.Bottom - 1;
  Volatile(aDeque^.Bottom) := B;
  // The new bottom must be visible before Top is read: a thief that read the
  // old bottom races for the same item through the CAS below
  ReadWriteBarrier;
  T := Volatile(aDeque^.Top);
  if T > B then
    begin
    Volatile(aDeque^.Bottom) := B + 1;
    Exit(False);
    end;
  aTask := aDeque^.Items[B and CDequeMask];
  if T = B then
    begin
    // The last item: thieves compete for it
    Result := InterlockedCompareExchange64(aDeque^.Top, T + 1, T) = T;
    Volatile(aDeque^.Bottom) := B + 1;
    end
  else
    Result := True;
end;

function DequeSteal(aDeque: PDeque; out aTask: TTask): Boolean;

var
  B, T: Int64;

begin
  T := Volatile(aDeque^.Top);
{$IF not (defined(CPUX86_64) or defined(CPUI386))}
  ReadBarrier;
{$ENDIF}
  B := Volatile(aDeque^.Bottom);
  if T >= B then
    Exit(False);
  // The slot can be overwritten only after Top moved on, and then the CAS
  // fails: a torn copy is never used
  aTask := aDeque^.Items[T and CDequeMask];
  Result := InterlockedCompareExchange64(aDeque^.Top, T + 1, T) = T;
end;

{ Tasks }

procedure CallRef(aCode: Pointer); inline;

var
  Proc: TProcRef absolute aCode;

begin
  Proc();
end;

procedure CallArg(aCode: Pointer; aArg: Int64); inline;

var
  Proc: TArgProc absolute aCode;

begin
  Proc(aArg);
end;

procedure ReleaseCode(aCode: Pointer); inline;

begin
  IUnknown(aCode)._Release;
end;

procedure AddRefCode(aCode: Pointer); inline;

begin
  IUnknown(aCode)._AddRef;
end;

procedure PushTask(var aTask: TTask); forward;

// Runs [aLow..aHigh]: the upper halves go to the deque, the lower half runs
// here, down to aGrain indices
procedure RunRange(aGroup: TTaskGroup; aCode: Pointer; aLow, aHigh, aGrain: Int64);

var
  Mid, I: Int64;
  Task: TTask;

begin
  while (aHigh - aLow + 1 > aGrain) and not aGroup.FCancelled do
    begin
    Mid := aLow + (aHigh - aLow) div 2;
    Task.Group := aGroup;
    Task.Code := aCode;
    Task.A := Mid + 1;
    Task.B := aHigh;
    Task.C := aGrain;
    Task.Kind := tkRange;
    AddRefCode(aCode);
    InterlockedIncrement64(aGroup.FPending);
    PushTask(Task);
    aHigh := Mid;
    end;
  I := aLow;
  while (I <= aHigh) and not aGroup.FCancelled do
    begin
    CallArg(aCode, I);
    Inc(I);
    end;
end;

procedure TaskDone(aGroup: TTaskGroup); inline;

begin
  // After the last decrement the group may be freed by its waiter: only the
  // pool is touched, with the group address as a key
  if InterlockedDecrement64(aGroup.FPending) = 0 then
    if Volatile(GPool.FParkedCount) > 0 then
      GPool.WakeGroupWaiters(aGroup);
end;

procedure RunTask(var aTask: TTask);

var
  Group: TTaskGroup;

begin
  Group := aTask.Group;
  try
    if not Group.FCancelled then
      case aTask.Kind of
        tkRef:
          CallRef(aTask.Code);
        tkArg:
          CallArg(aTask.Code, aTask.A);
        tkPlain:
          TPlainProc(aTask.Code)(Pointer(PtrUInt(aTask.A)));
        tkRange:
          RunRange(Group, aTask.Code, aTask.A, aTask.B, aTask.C);
      end;
  except
    Group.SetException(TObject(AcquireExceptionObject));
  end;
  if aTask.Kind <> tkPlain then
    ReleaseCode(aTask.Code);
  TaskDone(Group);
end;

procedure PushTask(var aTask: TTask);

var
  Deque: PDeque;

begin
  Deque := Pool.CurrentDeque;
  if (Deque <> nil) and DequePush(Deque, aTask) then
    GPool.Notify
  else
    // No deque for this thread or the deque is full: run it here
    RunTask(aTask);
end;

{ TWorker }

constructor TWorker.Create(aPool: TPool; aDeque: PDeque);

begin
  FPool := aPool;
  FDeque := aDeque;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TWorker.Execute;

var
  Task: TTask;
  Spins: Integer;

begin
  tvDeque := FDeque;
  Spins := 0;
  while not FPool.FStop do
    begin
    if FPool.FindTask(FDeque, Task) then
      begin
      Spins := 0;
      RunTask(Task);
      Continue;
      end;
    Inc(Spins);
    if Spins < CSpinRounds then
      CpuRelax
    else
      begin
      FPool.ParkWorker(FDeque);
      Spins := 0;
      end;
    end;
  if tvParkEvent <> nil then
    begin
    RTLEventDestroy(tvParkEvent);
    tvParkEvent := nil;
    end;
end;

{ TPool }

constructor TPool.Create;

var
  I, Count: Integer;

begin
  inherited Create;
  InitCriticalSection(FParkLock);
  Count := Integer(TThread.ProcessorCount) - 1;
  if Count < 1 then
    Count := 1;
  SetLength(FWorkers, Count);
  for I := 0 to Count - 1 do
    FWorkers[I] := TWorker.Create(Self, NewDeque);
end;

destructor TPool.Destroy;

var
  I: Integer;

begin
  FStop := True;
  EnterCriticalSection(FParkLock);
  try
    for I := 0 to FParkedCount - 1 do
      RTLEventSetEvent(FParked[I].Event);
  finally
    LeaveCriticalSection(FParkLock);
  end;
  for I := 0 to High(FWorkers) do
    begin
    FWorkers[I].WaitFor;
    FWorkers[I].Free;
    end;
  for I := 0 to FDequeCount - 1 do
    if (I < CMaxDeques) and (FDeques[I] <> nil) then
      FreeMem(FDeques[I]);
  DoneCriticalSection(FParkLock);
  inherited Destroy;
end;

function TPool.NewDeque: PDeque;

var
  Slot: LongInt;

begin
  Slot := InterlockedIncrement(FDequeCount) - 1;
  if Slot >= CMaxDeques then
    begin
    InterlockedDecrement(FDequeCount);
    Exit(nil);
    end;
  Result := GetMem(SizeOf(TDeque));
  Result^.Top := 0;
  Result^.Bottom := 0;
  // Thieves skip a slot that is still nil
  Volatile(FDeques[Slot]) := Result;
end;

function TPool.CurrentDeque: PDeque;

begin
  Result := tvDeque;
  if (Result = nil) and not tvNoDeque then
    begin
    Result := NewDeque;
    if Result = nil then
      tvNoDeque := True
    else
      tvDeque := Result;
    end;
end;

function TPool.TrySteal(aSelf: PDeque; out aTask: TTask): Boolean;

var
  Count, Start, I: LongInt;
  Victim: PDeque;

begin
  Count := Volatile(FDequeCount);
  if Count > CMaxDeques then
    Count := CMaxDeques;
  if Count = 0 then
    Exit(False);
  Start := LongInt(NextRandom mod LongWord(Count));
  for I := 0 to Count - 1 do
    begin
    Victim := Volatile(FDeques[(Start + I) mod Count]);
    if (Victim <> nil) and (Victim <> aSelf) and DequeSteal(Victim, aTask) then
      Exit(True);
    end;
  Result := False;
end;

function TPool.FindTask(aOwn: PDeque; out aTask: TTask): Boolean;

begin
  Result := ((aOwn <> nil) and DequePop(aOwn, aTask)) or TrySteal(aOwn, aTask);
  // More work may wait: pass the wake-up on to the next idle worker
  if Result and (Volatile(FIdleWorkers) > 0) then
    Notify;
end;

procedure TPool.Notify;

var
  I: Integer;

begin
  // The pushed item must be visible before the idle count is read; a worker
  // raises the count before its last look at the deques
  ReadWriteBarrier;
  if Volatile(FIdleWorkers) = 0 then
    Exit;
  // One wake-up in flight is enough: the woken worker passes it on
  if InterlockedCompareExchange(FWakeToken, 1, 0) <> 0 then
    Exit;
  EnterCriticalSection(FParkLock);
  try
    for I := 0 to FParkedCount - 1 do
      if FParked[I].Key = nil then
        begin
        RTLEventSetEvent(FParked[I].Event);
        Break;
        end;
  finally
    LeaveCriticalSection(FParkLock);
  end;
end;

procedure TPool.WakeGroupWaiters(aGroup: Pointer);

var
  I: Integer;

begin
  EnterCriticalSection(FParkLock);
  try
    for I := 0 to FParkedCount - 1 do
      if FParked[I].Key = aGroup then
        RTLEventSetEvent(FParked[I].Event);
  finally
    LeaveCriticalSection(FParkLock);
  end;
end;

function TPool.TryPark(aKey: Pointer; aEvent: PRTLEvent): Boolean;

begin
  EnterCriticalSection(FParkLock);
  try
    Result := FParkedCount < CMaxParked;
    if Result then
      begin
      FParked[FParkedCount].Key := aKey;
      FParked[FParkedCount].Event := aEvent;
      Inc(FParkedCount);
      end;
  finally
    LeaveCriticalSection(FParkLock);
  end;
end;

procedure TPool.Unpark(aEvent: PRTLEvent);

var
  I: Integer;

begin
  EnterCriticalSection(FParkLock);
  try
    for I := 0 to FParkedCount - 1 do
      if FParked[I].Event = aEvent then
        begin
        FParked[I] := FParked[FParkedCount - 1];
        Dec(FParkedCount);
        Break;
        end;
  finally
    LeaveCriticalSection(FParkLock);
  end;
end;

procedure TPool.ParkWorker(aDeque: PDeque);

var
  Event: PRTLEvent;
  Task: TTask;

begin
  Event := ParkEvent;
  InterlockedIncrement(FIdleWorkers);
  if not TryPark(nil, Event) then
    begin
    InterlockedDecrement(FIdleWorkers);
    ThreadSwitch;
    Exit;
    end;
  // Last look after raising the idle count: a push after this sees the count
  if not FStop and (((aDeque <> nil) and DequePop(aDeque, Task)) or TrySteal(aDeque, Task)) then
    begin
    Unpark(Event);
    InterlockedDecrement(FIdleWorkers);
    // A wake-up may have been aimed at this worker: let the next one through
    FWakeToken := 0;
    RunTask(Task);
    Exit;
    end;
  if not FStop then
    // The timeout only guards against a lost wake-up
    RTLEventWaitFor(Event, 100);
  Unpark(Event);
  InterlockedDecrement(FIdleWorkers);
  // This worker took the wake-up in flight
  FWakeToken := 0;
end;

procedure TPool.ParkWaiter(aGroup: TTaskGroup);

var
  Event: PRTLEvent;

begin
  Event := ParkEvent;
  if not TryPark(aGroup, Event) then
    begin
    ThreadSwitch;
    Exit;
    end;
  // The last task decrements FPending and then looks at the parked list:
  // either it sees this entry or this check sees zero
  if Volatile(aGroup.FPending) > 0 then
    RTLEventWaitFor(Event, 100);
  Unpark(Event);
end;

{ TTaskGroup }

constructor TTaskGroup.Create;

begin
  inherited Create;
  Pool;
end;

destructor TTaskGroup.Destroy;

begin
  WaitForTasks;
  if FException <> nil then
    TObject(FException).Free;
  inherited Destroy;
end;

procedure TTaskGroup.SetException(aObject: TObject);

begin
  if InterlockedCompareExchange(FException, Pointer(aObject), nil) <> nil then
    aObject.Free
  else
    begin
    FCancelledByError := True;
    FCancelled := True;
    end;
end;

procedure TTaskGroup.Spawn(const aProc: TProcRef);

var
  Task: TTask;

begin
  Task.Group := Self;
  Task.Code := Pointer(aProc);
  Task.Kind := tkRef;
  AddRefCode(Task.Code);
  InterlockedIncrement64(FPending);
  PushTask(Task);
end;

procedure TTaskGroup.Spawn(aArg: Int64; const aProc: TArgProc);

var
  Task: TTask;

begin
  Task.Group := Self;
  Task.Code := Pointer(aProc);
  Task.A := aArg;
  Task.Kind := tkArg;
  AddRefCode(Task.Code);
  InterlockedIncrement64(FPending);
  PushTask(Task);
end;

procedure TTaskGroup.Spawn(aProc: TPlainProc; aData: Pointer);

var
  Task: TTask;

begin
  Task.Group := Self;
  Task.Code := Pointer(aProc);
  Task.A := Int64(PtrUInt(aData));
  Task.Kind := tkPlain;
  InterlockedIncrement64(FPending);
  PushTask(Task);
end;

procedure TTaskGroup.WaitForTasks;

var
  Task: TTask;
  Own: PDeque;
  Spins: Integer;

begin
  Own := tvDeque;
  Spins := 0;
  while Volatile(FPending) > 0 do
    begin
    if GPool.FindTask(Own, Task) then
      begin
      Spins := 0;
      RunTask(Task);
      Continue;
      end;
    Inc(Spins);
    if Spins < CSpinRounds then
      CpuRelax
    else
      begin
      GPool.ParkWaiter(Self);
      Spins := 0;
      end;
    end;
end;

procedure TTaskGroup.Wait;

var
  E: Pointer;

begin
  WaitForTasks;
  E := InterlockedExchange(FException, nil);
  if FCancelledByError then
    begin
    FCancelledByError := False;
    FCancelled := False;
    end;
  if E <> nil then
    raise TObject(E);
end;

procedure TTaskGroup.Cancel;

begin
  FCancelled := True;
end;

function TTaskGroup.IsCancelled: Boolean;

begin
  Result := FCancelled;
end;

{ TForkJoin }

class procedure TForkJoin.Each(aLow, aHigh: Int64; const aProc: TArgProc; aGrain: Int64);

var
  Group: TTaskGroup;

begin
  if aHigh < aLow then
    Exit;
  if aGrain <= 0 then
    begin
    aGrain := (aHigh - aLow + 1) div (8 * (WorkerCount + 1));
    if aGrain < 1 then
      aGrain := 1;
    end;
  Group := TTaskGroup.Create;
  try
    try
      RunRange(Group, Pointer(aProc), aLow, aHigh, aGrain);
    except
      Group.SetException(TObject(AcquireExceptionObject));
    end;
    Group.Wait;
  finally
    Group.Free;
  end;
end;

class procedure TForkJoin.Join(const aFirst, aSecond: TProcRef);

var
  Group: TTaskGroup;

begin
  Group := TTaskGroup.Create;
  try
    Group.Spawn(aSecond);
    try
      aFirst();
    except
      Group.SetException(TObject(AcquireExceptionObject));
    end;
    Group.Wait;
  finally
    Group.Free;
  end;
end;

class function TForkJoin.WorkerCount: Integer;

begin
  Result := Length(Pool.FWorkers);
end;

initialization
  InitCriticalSection(GPoolLock);
finalization
  FreeAndNil(GPool);
  DoneCriticalSection(GPoolLock);
end.
