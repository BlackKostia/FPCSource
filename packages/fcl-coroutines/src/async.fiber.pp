{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 2026 by the Free Pascal development team

    High-Performance User-Space Fibers and Coroutines (Phase 4, Step 1)
    Non-blocking fiber suspension, resumption, and async integration

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.
}
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}

unit async.fiber;

interface

uses
  {$IFDEF UNIX}cthreads, baseunix, unixtype,{$ENDIF}
  SysUtils, Classes, SyncObjs,
  System.Threading,
  eventloop.types, eventloop.core, eventloop.sockets,
  async.types, async.statemachine;

type
  { Internal: body of a TFiber.Async coroutine. A class rather than an
    anonymous function, which FPC cannot compile inside a generic method
    that is specialized in another unit. }
  generic TFiberAsyncBody<T> = class
  public
    Func: specialize TFunc<T>;
    Source: specialize TTaskCompletionSource<T>;
    procedure Execute;
  end;

  TFiber = class
  private
    FStackBase: Pointer;
    FStackSize: Cardinal;
    FSavedRsp: Pointer;
    FCallerRsp: Pointer;
    FState: TFiberState;
    FProc: TFiberProc;
    FMethod: TFiberMethod;
    FProcRef: TProc;
    FSuspendOnWait: Boolean;
    FFreeOnFinish: Boolean;
    FException: Exception;
    FEventLoop: IEventLoop;
    FUserData: Pointer;
    FSavedExceptAddr: Pointer;
    FCallerExceptAddr: Pointer;
    FSavedExceptObj: Pointer;
    FCallerExceptObj: Pointer;
    FCallerStackBottom: Pointer;
    { 1 while the fiber is not executing on any thread. A resume that comes
      from another thread (a future's continuation, a pool task) waits for
      it, because the fiber may not have finished switching out yet. }
    FParked: LongInt;
    FStackMapSize: PtrUInt;
    procedure InitStack;
    procedure WaitParked;
    class procedure ResumeFromOtherThread(AFiber: TFiber); static;
    procedure Init(AStackSize: Cardinal; ALoop: IEventLoop);
    procedure Run;
    procedure OnSleepTimer(ATimerId: Int64);
    procedure OnContinuation(ATask: ITask);
    procedure ScheduleResume;
    procedure SuspendUntil(const ATask: ITask);
    class procedure Start(AFiber: TFiber); static;
  public
    constructor Create(AProc: TFiberProc; AStackSize: Cardinal = 128 * 1024; ALoop: IEventLoop = nil); overload;
    constructor Create(AMethod: TFiberMethod; AStackSize: Cardinal = 128 * 1024; ALoop: IEventLoop = nil); overload;
    constructor Create(const AProc: TProc; AStackSize: Cardinal = 128 * 1024; ALoop: IEventLoop = nil); overload;
    destructor Destroy; override;

    { Execute / resume fiber execution }
    procedure Resume;

    { Yield current fiber execution back to caller / scheduler }
    class procedure Yield; static;

    { Current executing fiber in the current thread }
    class function Current: TFiber; static;

    { Non-blocking await of IFuture<T> without OS thread blocking }
    generic class function Await<T>(const AFuture: specialize IFuture<T>): T; overload; static;
    class procedure Await(const ATask: ITask); overload; static;

    { Non-blocking sleep: yields fiber to event loop until timer expiry }
    class procedure Sleep(AMilliseconds: Cardinal; ALoop: IEventLoop = nil); static;

    { Runs AFunc as a coroutine and returns a future for its result, like an
      async method: AFunc runs in the calling thread (or, with ALoop, in the
      loop's thread) until it first waits for an unfinished task - with
      await, IFuture.Value, ITask.Wait or TTask.WaitForAll - and the call
      returns then. The coroutine continues when the task has finished: in
      ALoop's thread, or without a loop in a pool thread. The fiber frees
      itself when AFunc returns. }
    generic class function Async<T>(const AFunc: specialize TFunc<T>; ALoop: IEventLoop = nil;
      AStackSize: Cardinal = 128 * 1024): specialize IFuture<T>; static;
    { The same for a procedure; the task completes when AProc returns. }
    class function Spawn(const AProc: TProc; ALoop: IEventLoop = nil;
      AStackSize: Cardinal = 128 * 1024): ITask; static;

    { Non-blocking socket read/write inside fibers }
    class function AwaitRead(ASocket: IAsyncSocket; ABuffer: Pointer; ACount: NativeInt): NativeInt; static;
    class function AwaitWrite(ASocket: IAsyncSocket; ABuffer: Pointer; ACount: NativeInt): NativeInt; static;

    property State: TFiberState read FState;
    property EventLoop: IEventLoop read FEventLoop write FEventLoop;
    property FatalException: Exception read FException;
    property UserData: Pointer read FUserData write FUserData;
    { True (the default): a wait without timeout for an unfinished task in
      this fiber (await, IFuture.Value, ITask.Wait, TTask.WaitForAll)
      suspends the fiber instead of blocking the thread. Generators set it
      to False: their fiber must only switch at Yield. }
    property SuspendOnWait: Boolean read FSuspendOnWait write FSuspendOnWait;
  end;

{ Helper routines for compiler-generated lower_async_fiber phase }
generic function AsyncFiberRun<T>(const AFunc: specialize TFunc<T>): specialize IFuture<T>;
function AsyncFiberRunTask(const AProc: TProc): ITask;

implementation

threadvar
  GCurrentFiber: TFiber;

{$IFDEF FPC_SECTION_THREADVARS}
{ Threadvars live in the ELF TLS section: the private exception stacks of
  System are declared as external threadvars and reached through %fs.
  Referencing them as plain variables fails to link (TLS definition
  mismatches non-TLS reference). }
threadvar
  U_EXCEPTADDRSTACK: Pointer; external name 'U_$SYSTEM_$$_EXCEPTADDRSTACK';
  U_EXCEPTOBJECTSTACK: Pointer; external name 'U_$SYSTEM_$$_EXCEPTOBJECTSTACK';

var
  { Typed const in System. fpc_stackcheck treats this many bytes above
    StackBottom as already exhausted. }
  SystemStackMargin: PtrUInt; external name 'TC_$SYSTEM_$$_STACKMARGIN';

function GetExceptAddrStackPtr: PPointer;
begin
  Result := @U_EXCEPTADDRSTACK;
end;

function GetExceptObjectStackPtr: PPointer;
begin
  Result := @U_EXCEPTOBJECTSTACK;
end;

function GetStackBottomPtr: PPointer;
begin
  Result := @StackBottom;
end;
{$ELSE FPC_SECTION_THREADVARS}
type
  TThreadVarRelocateFunc = function(offset: DWord): Pointer;

var
  FPC_THREADVAR_RELOCATE: TThreadVarRelocateFunc; external name 'FPC_THREADVAR_RELOCATE';
  U_EXCEPTADDRSTACK: array[0..15] of Byte; external name 'U_$SYSTEM_$$_EXCEPTADDRSTACK';
  U_EXCEPTOBJECTSTACK: array[0..15] of Byte; external name 'U_$SYSTEM_$$_EXCEPTOBJECTSTACK';
  U_STACKBOTTOM: array[0..15] of Byte; external name 'U_$SYSTEM_$$_STACKBOTTOM';
  { Typed const in System. fpc_stackcheck treats this many bytes above
    StackBottom as already exhausted. }
  SystemStackMargin: PtrUInt; external name 'TC_$SYSTEM_$$_STACKMARGIN';

function GetExceptAddrStackPtr: PPointer;
begin
  if Assigned(FPC_THREADVAR_RELOCATE) then
    Result := PPointer(FPC_THREADVAR_RELOCATE(PDWord(@U_EXCEPTADDRSTACK)^))
  else
    Result := PPointer(@U_EXCEPTADDRSTACK[8]);
end;

function GetExceptObjectStackPtr: PPointer;
begin
  if Assigned(FPC_THREADVAR_RELOCATE) then
    Result := PPointer(FPC_THREADVAR_RELOCATE(PDWord(@U_EXCEPTOBJECTSTACK)^))
  else
    Result := PPointer(@U_EXCEPTOBJECTSTACK[8]);
end;

function GetStackBottomPtr: PPointer;
begin
  if Assigned(FPC_THREADVAR_RELOCATE) then
    Result := PPointer(FPC_THREADVAR_RELOCATE(PDWord(@U_STACKBOTTOM)^))
  else
    Result := PPointer(@U_STACKBOTTOM[8]);
end;
{$ENDIF FPC_SECTION_THREADVARS}

{$IFDEF CPUX86_64}
{
  Fast Assembly Context Switch for System V AMD64 ABI:
  RDI: var CurrentRsp: Pointer
  RSI: TargetRsp: Pointer
}
procedure FiberSwitchContext(var CurrentRsp: Pointer; TargetRsp: Pointer); assembler; nostackframe;
asm
  pushq %rbx
  pushq %rbp
  pushq %r12
  pushq %r13
  pushq %r14
  pushq %r15
  movq  %rsp, (%rdi)
  movq  %rsi, %rsp
  popq  %r15
  popq  %r14
  popq  %r13
  popq  %r12
  popq  %rbp
  popq  %rbx
  ret
end;
{$ELSE}
{$FATAL TFiber context switch currently requires x86_64 CPU architecture}
{$ENDIF}

procedure FiberEntryTrampoline;
var
  LFiber: TFiber;
begin
  LFiber := GCurrentFiber;
  if LFiber <> nil then
    LFiber.Run;
end;

{ TFiber }

const
  FiberGuardSize = 4096;

procedure TFiber.InitStack;
var
  LSp: PPointer;
begin
  {$IFDEF UNIX}
  { Allocate private anonymous memory for the fiber stack, with an
    inaccessible guard page below it: a stack overflow then faults instead
    of silently overwriting whatever memory lies below the stack. }
  FStackMapSize := FStackSize + FiberGuardSize;
  FStackBase := Fpmmap(nil, FStackMapSize, PROT_READ or PROT_WRITE, MAP_PRIVATE or MAP_ANONYMOUS, -1, 0);
  if FStackBase = MAP_FAILED then
  begin
    FStackBase := nil;
    raise EFiberException.CreateFmt('Failed to allocate fiber stack (%d bytes)', [FStackSize]);
  end;
  Fpmprotect(FStackBase, FiberGuardSize, PROT_NONE);
  {$ELSE}
  FStackMapSize := FStackSize + FiberGuardSize;
  GetMem(FStackBase, FStackMapSize);
  {$ENDIF}

  { Setup stack growing downwards, 16-byte aligned }
  LSp := PPointer(PByte(FStackBase) + FStackMapSize);

  { 16-byte ABI alignment word: ret pops trampoline, leaving rsp at 8 mod 16 }
  Dec(LSp);
  LSp^ := nil;

  { Push trampoline return address }
  Dec(LSp);
  LSp^ := @FiberEntryTrampoline;

  { Push 6 callee-saved registers (r15, r14, r13, r12, rbp, rbx) }
  Dec(LSp); LSp^ := nil; { r15 }
  Dec(LSp); LSp^ := nil; { r14 }
  Dec(LSp); LSp^ := nil; { r13 }
  Dec(LSp); LSp^ := nil; { r12 }
  Dec(LSp); LSp^ := nil; { rbp }
  Dec(LSp); LSp^ := nil; { rbx }

  FSavedRsp := LSp;
end;

constructor TFiber.Create(AProc: TFiberProc; AStackSize: Cardinal; ALoop: IEventLoop);
begin
  inherited Create;
  FProc := AProc;
  Init(AStackSize, ALoop);
end;

constructor TFiber.Create(AMethod: TFiberMethod; AStackSize: Cardinal; ALoop: IEventLoop);
begin
  inherited Create;
  FMethod := AMethod;
  Init(AStackSize, ALoop);
end;

constructor TFiber.Create(const AProc: TProc; AStackSize: Cardinal; ALoop: IEventLoop);
begin
  inherited Create;
  FProcRef := AProc;
  Init(AStackSize, ALoop);
end;

procedure TFiber.Init(AStackSize: Cardinal; ALoop: IEventLoop);
begin
  FParked := 1;
  FSuspendOnWait := True;
  FStackSize := (AStackSize + 4095) and not 4095; { Round to 4KB page }
  if FStackSize < 16384 then
    FStackSize := 16384;
  FState := fsCreated;
  FEventLoop := ALoop;
  FException := nil;
  FUserData := nil;
  InitStack;
end;

destructor TFiber.Destroy;
begin
  if FState = fsRunning then
    raise EInvalidFiberOperation.Create('Cannot destroy an actively running fiber');
  { State becomes fsCompleted (or fsSuspended) just before the fiber switches
    out. Another thread can see it while the fiber still runs on its stack:
    wait until the switch is done before unmapping the stack. }
  if FStackBase <> nil then
    WaitParked;

  if FStackBase <> nil then
  begin
    {$IFDEF UNIX}
    Fpmunmap(FStackBase, FStackMapSize);
    {$ELSE}
    FreeMem(FStackBase);
    {$ENDIF}
    FStackBase := nil;
  end;

  FException.Free;
  inherited Destroy;
end;

procedure TFiber.Run;
begin
  try
    if Assigned(FProc) then
      FProc
    else if Assigned(FMethod) then
      FMethod
    else if Assigned(FProcRef) then
      FProcRef();
    FState := fsCompleted;
  except
    on E: Exception do
    begin
      FState := fsFaulted;
      FException := Exception(AcquireExceptionObject);
    end;
  end;

  { Execution finished; switch back to caller context }
  Yield;
end;

procedure TFiber.WaitParked;
var
  LSpins: Integer;
begin
  LSpins := 0;
  while InterlockedCompareExchange(FParked, 0, 0) = 0 do
  begin
    Inc(LSpins);
    if LSpins > 100 then
      ThreadSwitch;
  end;
  ReadBarrier;
end;

class procedure TFiber.ResumeFromOtherThread(AFiber: TFiber);
begin
  AFiber.WaitParked;
  AFiber.Resume;
end;

procedure TFiber.Resume;
var
  LPrevFiber: TFiber;
  LAddrPtr, LObjPtr: PPointer;
  LError: Exception;
begin
  if FState in [fsCompleted, fsFaulted] then
    raise EInvalidFiberOperation.Create('Cannot resume an already completed or faulted fiber');
  if GCurrentFiber = Self then
    raise EInvalidFiberOperation.Create('A fiber cannot resume itself');
  if InterlockedExchange(FParked, 0) = 0 then
    raise EInvalidFiberOperation.Create('Fiber is already running');

  LAddrPtr := GetExceptAddrStackPtr;
  LObjPtr := GetExceptObjectStackPtr;

  LPrevFiber := GCurrentFiber;
  GCurrentFiber := Self;
  FState := fsRunning;

  { Save caller exception stack and install fiber's exception stack }
  FCallerExceptAddr := LAddrPtr^;
  FCallerExceptObj := LObjPtr^;
  LAddrPtr^ := FSavedExceptAddr;
  LObjPtr^ := FSavedExceptObj;

  { fpc_stackcheck compares SP with this thread's stack limit and keeps
    SystemStackMargin bytes in reserve. The fiber runs on its own mapping,
    so the limit has to move with the context or the trampoline raises
    EStackOverflow before the first statement. The reserve sits below the
    guard page: a fiber stack may be only as large as that margin, and the
    guard page is what stops a real overflow. }
  FCallerStackBottom := GetStackBottomPtr^;
  GetStackBottomPtr^ := PByte(FStackBase) + FiberGuardSize - SystemStackMargin;

  FiberSwitchContext(FCallerRsp, FSavedRsp);

  { Yield restores StackBottom before switching back. Doing it here would
    call into a stack-checked routine while SP is already on this thread
    and the limit still belongs to the fiber. }

  { Context has returned to caller; Yield already saved fiber and restored caller context }
  GCurrentFiber := LPrevFiber;
  { From here on the fiber's stack is not in use: another thread may resume it. }
  WriteBarrier;
  InterlockedExchange(FParked, 1);

  if FFreeOnFinish and (FState in [fsCompleted, fsFaulted]) then
  begin
    { An Async fiber has passed its outcome on to its future. }
    Free;
    Exit;
  end;

  if (FState = fsFaulted) and (FException <> nil) then
  begin
    { FatalException stays owned by the fiber; raise a new exception of the
      same class so that "on E: EMyError do" handlers still match. }
    LError := ExceptClass(FException.ClassType).Create(FException.Message);
    raise LError;
  end;
end;

class procedure TFiber.Yield;
var
  LCur: TFiber;
  LAddrPtr, LObjPtr: PPointer;
begin
  LCur := GCurrentFiber;
  if LCur = nil then
    raise EInvalidFiberOperation.Create('Cannot yield: no fiber is currently executing');

  if LCur.FState = fsRunning then
    LCur.FState := fsSuspended;

  LAddrPtr := GetExceptAddrStackPtr;
  LObjPtr := GetExceptObjectStackPtr;

  { Save fiber exception stack and restore caller's exception stack }
  LCur.FSavedExceptAddr := LAddrPtr^;
  LCur.FSavedExceptObj := LObjPtr^;
  LAddrPtr^ := LCur.FCallerExceptAddr;
  LObjPtr^ := LCur.FCallerExceptObj;

  { Still on the fiber stack, so the stack check matches this limit.
    Restore the caller's limit before switching: the caller's next
    call must not be checked against the fiber. }
  GetStackBottomPtr^ := LCur.FCallerStackBottom;

  FiberSwitchContext(LCur.FSavedRsp, LCur.FCallerRsp);

  { When we return here, Resume has already saved caller context and restored fiber context }
end;

class function TFiber.Current: TFiber;
begin
  Result := GCurrentFiber;
end;

procedure TFiber.OnSleepTimer(ATimerId: Int64);
begin
  { The loop may run in another thread than the fiber. }
  TFiber.ResumeFromOtherThread(Self);
end;

procedure TFiber.OnContinuation(ATask: ITask);
begin
  ScheduleResume;
end;

procedure TFiber.ScheduleResume;
var
  LFiber: TFiber;
begin
  LFiber := Self;
  { A plain work item, not a task: a task created here would inherit the
    cancellation token of whatever task runs in this thread, and a canceled
    resume would leave the fiber suspended for ever. }
  if FEventLoop <> nil then
    FEventLoop.Post(procedure begin TFiber.ResumeFromOtherThread(LFiber); end)
  else
    TThreadPool.Default.QueueWorkItem(procedure begin TFiber.ResumeFromOtherThread(LFiber); end);
end;

procedure TFiber.SuspendUntil(const ATask: ITask);
var
  LFiber: TFiber;
begin
  LFiber := Self;
  FState := fsSuspended;
  { The completion callback runs in the thread that completes the task, or
    at once if it is already complete; ScheduleResume waits until the fiber
    has really switched out. }
  TaskOnComplete(ATask,
    procedure
    begin
      LFiber.ScheduleResume;
    end);
  Yield;
end;

class procedure TFiber.Start(AFiber: TFiber);
var
  LFiber: TFiber;
begin
  LFiber := AFiber;
  if (LFiber.FEventLoop <> nil) and not LFiber.FEventLoop.InLoopThread then
    LFiber.FEventLoop.Post(procedure begin LFiber.Resume; end)
  else
    LFiber.Resume;
end;

procedure TFiberAsyncBody.Execute;
var
  LRes: T;
begin
  try
    LRes := Func();
    Source.SetResult(LRes);
  except
    Source.SetException(Exception(AcquireExceptionObject));
  end;
  Source.Free; { the task stays valid }
  Free;
end;

generic class function TFiber.Async<T>(const AFunc: specialize TFunc<T>; ALoop: IEventLoop;
  AStackSize: Cardinal): specialize IFuture<T>;
var
  LBody: specialize TFiberAsyncBody<T>;
  LFiber: TFiber;
begin
  { Without a loop, a coroutine started from a coroutine stays on that
    coroutine's loop (like an async call inside an async method). }
  if (ALoop = nil) and (Current <> nil) then
    ALoop := Current.EventLoop;
  LBody := specialize TFiberAsyncBody<T>.Create;
  LBody.Func := AFunc;
  LBody.Source := specialize TTaskCompletionSource<T>.Create;
  Result := LBody.Source.Task;
  LFiber := TFiber.Create(@LBody.Execute, AStackSize, ALoop);
  LFiber.FFreeOnFinish := True;
  Start(LFiber);
end;

class function TFiber.Spawn(const AProc: TProc; ALoop: IEventLoop; AStackSize: Cardinal): ITask;
var
  LSource: specialize TTaskCompletionSource<Boolean>;
  LFiber: TFiber;
begin
  if (ALoop = nil) and (GCurrentFiber <> nil) then
    ALoop := GCurrentFiber.FEventLoop;
  LSource := specialize TTaskCompletionSource<Boolean>.Create;
  Result := LSource.Task;
  LFiber := TFiber.Create(
    procedure
    begin
      try
        AProc();
        LSource.SetResult(True);
      except
        LSource.SetException(Exception(AcquireExceptionObject));
      end;
      LSource.Free;
    end, AStackSize, ALoop);
  LFiber.FFreeOnFinish := True;
  Start(LFiber);
end;

{ Installed as System.Threading.TaskAwaitHook }
function FiberAwaitHook(const aTask: ITask): Boolean;
var
  LFiber: TFiber;
begin
  LFiber := GCurrentFiber;
  Result := (LFiber <> nil) and LFiber.FSuspendOnWait and (aTask <> nil);
  if Result then
    LFiber.SuspendUntil(aTask);
end;

generic class function TFiber.Await<T>(const AFuture: specialize IFuture<T>): T;
var
  LFiber: TFiber;
begin
  if AFuture = nil then
    raise EArgumentNilException.Create('AFuture cannot be nil in TFiber.Await');

  if AFuture.Status = TTaskStatus.Completed then
    Exit(AFuture.Value);

  if AFuture.Status in [TTaskStatus.Canceled, TTaskStatus.Exception] then
    Exit(AFuture.Value); { Raises exception }

  LFiber := Current;
  if LFiber = nil then
    raise EFiberException.Create('TFiber.Await must be called from inside an active fiber');

  LFiber.SuspendUntil(AFuture);

  Result := AFuture.Value;
end;

class procedure TFiber.Await(const ATask: ITask);
var
  LFiber: TFiber;
begin
  if ATask = nil then
    raise EArgumentNilException.Create('ATask cannot be nil in TFiber.Await');

  if ATask.Status = TTaskStatus.Completed then
    Exit;

  if ATask.Status in [TTaskStatus.Canceled, TTaskStatus.Exception] then
  begin
    ATask.Wait;
    Exit;
  end;

  LFiber := Current;
  if LFiber = nil then
    raise EFiberException.Create('TFiber.Await must be called from inside an active fiber');

  LFiber.SuspendUntil(ATask);

  if ATask.Status in [TTaskStatus.Canceled, TTaskStatus.Exception] then
    ATask.Wait;
end;

class procedure TFiber.Sleep(AMilliseconds: Cardinal; ALoop: IEventLoop);
var
  LFiber: TFiber;
  LLoop: IEventLoop;
begin
  LFiber := Current;
  if LFiber = nil then
  begin
    SysUtils.Sleep(AMilliseconds);
    Exit;
  end;

  LLoop := ALoop;
  if LLoop = nil then
    LLoop := LFiber.FEventLoop;

  LFiber.FState := fsSuspended;
  if LLoop <> nil then
  begin
    LLoop.SetTimer(AMilliseconds, @LFiber.OnSleepTimer, False);
    Yield;
  end
  else
  begin
    TThreadPool.Default.QueueWorkItem(
      procedure
      begin
        SysUtils.Sleep(AMilliseconds);
        TFiber.ResumeFromOtherThread(LFiber);
      end);
    Yield;
  end;
end;

class function TFiber.AwaitRead(ASocket: IAsyncSocket; ABuffer: Pointer; ACount: NativeInt): NativeInt;
var
  LFiber: TFiber;
  LBytesRead: NativeInt;
  LStatus: Integer;
begin
  LFiber := Current;
  if LFiber = nil then
    raise EFiberException.Create('TFiber.AwaitRead must be called from inside a fiber');

  LFiber.FState := fsSuspended;
  LBytesRead := 0;
  LStatus := 0;

  ASocket.AsyncRead(ABuffer, ACount,
    procedure(ABytes: NativeInt; AStat: Integer)
    begin
      LBytesRead := ABytes;
      LStatus := AStat;
      { The fiber may be resumed only after it has yielded, so the resume
        always goes through Post or a pool task. }
      if LFiber.FEventLoop <> nil then
        LFiber.FEventLoop.Post(procedure begin TFiber.ResumeFromOtherThread(LFiber); end)
      else
        TThreadPool.Default.QueueWorkItem(procedure begin TFiber.ResumeFromOtherThread(LFiber); end);
    end);

  Yield;

  if LStatus <> 0 then
    raise ESocketException.CreateFmt('Async read failed with error %d', [LStatus]);
  Result := LBytesRead;
end;

class function TFiber.AwaitWrite(ASocket: IAsyncSocket; ABuffer: Pointer; ACount: NativeInt): NativeInt;
var
  LFiber: TFiber;
  LBytesWritten: NativeInt;
  LStatus: Integer;
begin
  LFiber := Current;
  if LFiber = nil then
    raise EFiberException.Create('TFiber.AwaitWrite must be called from inside a fiber');

  LFiber.FState := fsSuspended;
  LBytesWritten := 0;
  LStatus := 0;

  ASocket.AsyncWrite(ABuffer, ACount,
    procedure(ABytes: NativeInt; AStat: Integer)
    begin
      LBytesWritten := ABytes;
      LStatus := AStat;
      { The fiber may be resumed only after it has yielded, so the resume
        always goes through Post or a pool task. }
      if LFiber.FEventLoop <> nil then
        LFiber.FEventLoop.Post(procedure begin TFiber.ResumeFromOtherThread(LFiber); end)
      else
        TThreadPool.Default.QueueWorkItem(procedure begin TFiber.ResumeFromOtherThread(LFiber); end);
    end);

  Yield;

  if LStatus <> 0 then
    raise ESocketException.CreateFmt('Async write failed with error %d', [LStatus]);
  Result := LBytesWritten;
end;

generic function AsyncFiberRun<T>(const AFunc: specialize TFunc<T>): specialize IFuture<T>;
begin
  Result := TFiber.specialize Async<T>(AFunc);
end;

function AsyncFiberRunTask(const AProc: TProc): ITask;
begin
  Result := TFiber.Spawn(AProc);
end;

initialization
  TaskAwaitHook := @FiberAwaitHook;
finalization
  if TaskAwaitHook = @FiberAwaitHook then
    TaskAwaitHook := nil;
end.
