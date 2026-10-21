unit utforkjoin;

{$mode objfpc}{$H+}

{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, system.threading.forkjoin;

type
  EForkJoinTest = class(Exception);

  { TTestForkJoin }

  TTestForkJoin = class(TTestCase)
  published
    procedure TestSpawnRefRunsEachOnce;
    procedure TestSpawnArgPassesArgument;
    procedure TestSpawnPlainProc;
    procedure TestWaitWithoutTasks;
    procedure TestNestedGroups;
    procedure TestFirstExceptionReraised;
    procedure TestGroupUsableAfterException;
    procedure TestCancelSkipsQueuedTasks;
    procedure TestEachCoversRangeOnce;
    procedure TestEachEmptyAndSingle;
    procedure TestEachGrain;
    procedure TestEachException;
    procedure TestJoinRunsBoth;
    procedure TestSpawnFromSeveralThreads;
    procedure TestDestroyWaitsForTasks;
    procedure TestWorkerCount;
  end;

implementation

const
  CTaskCount = 100000;

var
  GPlainCounter: Int64;

procedure PlainIncrement(aData: Pointer);

begin
  InterlockedIncrement64(GPlainCounter);
  InterlockedExchangeAdd64(PInt64(aData)^, 1);
end;

// Recursive Fibonacci with a group per level: nested Wait inside tasks
function Fib(N: Integer): Int64;

var
  A, B: Int64;
  Group: TTaskGroup;

begin
  if N < 15 then
    begin
    if N < 2 then
      Exit(N);
    Exit(Fib(N - 1) + Fib(N - 2));
    end;
  A := 0;
  Group := TTaskGroup.Create;
  try
    Group.Spawn(procedure begin A := Fib(N - 1); end);
    B := Fib(N - 2);
    Group.Wait;
  finally
    Group.Free;
  end;
  Result := A + B;
end;

{ TTestForkJoin }

procedure TTestForkJoin.TestSpawnRefRunsEachOnce;

var
  Group: TTaskGroup;
  Count: Int64;
  Hits: array of LongInt;
  I: Integer;

begin
  Count := 0;
  SetLength(Hits, CTaskCount);
  Group := TTaskGroup.Create;
  try
    for I := 1 to CTaskCount do
      Group.Spawn(procedure begin InterlockedIncrement64(Count); end);
    for I := 0 to CTaskCount - 1 do
      Group.Spawn(I, procedure(aArg: Int64) begin InterlockedIncrement(Hits[aArg]); end);
    Group.Wait;
  finally
    Group.Free;
  end;
  AssertEquals(CTaskCount, Count);
  for I := 0 to CTaskCount - 1 do
    if Hits[I] <> 1 then
      Fail(Format('Index %d ran %d times', [I, Hits[I]]));
end;

procedure TTestForkJoin.TestSpawnArgPassesArgument;

var
  Group: TTaskGroup;
  Sum: Int64;
  I: Integer;

begin
  Sum := 0;
  Group := TTaskGroup.Create;
  try
    for I := 1 to CTaskCount do
      Group.Spawn(I, procedure(aArg: Int64) begin InterlockedExchangeAdd64(Sum, aArg); end);
    Group.Wait;
  finally
    Group.Free;
  end;
  AssertEquals(Int64(CTaskCount) * (CTaskCount + 1) div 2, Sum);
end;

procedure TTestForkJoin.TestSpawnPlainProc;

var
  Group: TTaskGroup;
  Local: Int64;
  I: Integer;

begin
  GPlainCounter := 0;
  Local := 0;
  Group := TTaskGroup.Create;
  try
    for I := 1 to CTaskCount do
      Group.Spawn(@PlainIncrement, @Local);
    Group.Wait;
  finally
    Group.Free;
  end;
  AssertEquals(CTaskCount, GPlainCounter);
  AssertEquals(CTaskCount, Local);
end;

procedure TTestForkJoin.TestWaitWithoutTasks;

var
  Group: TTaskGroup;

begin
  Group := TTaskGroup.Create;
  try
    Group.Wait;
    Group.Wait;
  finally
    Group.Free;
  end;
end;

procedure TTestForkJoin.TestNestedGroups;

begin
  AssertEquals(832040, Fib(30));
end;

procedure TTestForkJoin.TestFirstExceptionReraised;

var
  Group: TTaskGroup;
  Raised: Boolean;
  I: Integer;

begin
  Raised := False;
  Group := TTaskGroup.Create;
  try
    for I := 1 to 1000 do
      Group.Spawn(I, procedure(aArg: Int64)
        begin
        if aArg mod 100 = 0 then
          raise EForkJoinTest.Create('task ' + IntToStr(aArg));
        end);
    try
      Group.Wait;
    except
      on E: EForkJoinTest do
        Raised := True;
    end;
  finally
    Group.Free;
  end;
  AssertTrue('Wait re-raises the exception of a task', Raised);
end;

procedure TTestForkJoin.TestGroupUsableAfterException;

var
  Group: TTaskGroup;
  Count: Int64;

begin
  Count := 0;
  Group := TTaskGroup.Create;
  try
    Group.Spawn(procedure begin raise EForkJoinTest.Create('once'); end);
    try
      Group.Wait;
      Fail('Expected an exception');
    except
      on E: EForkJoinTest do ;
    end;
    // The exception was handed out: the group starts clean
    Group.Spawn(procedure begin InterlockedIncrement64(Count); end);
    Group.Wait;
  finally
    Group.Free;
  end;
  AssertEquals(1, Count);
end;

procedure TTestForkJoin.TestCancelSkipsQueuedTasks;

var
  Group: TTaskGroup;
  Count: Int64;
  I: Integer;

begin
  Count := 0;
  Group := TTaskGroup.Create;
  try
    Group.Cancel;
    AssertTrue(Group.IsCancelled);
    for I := 1 to 1000 do
      Group.Spawn(procedure begin InterlockedIncrement64(Count); end);
    Group.Wait;
  finally
    Group.Free;
  end;
  AssertEquals('Tasks of a cancelled group do not run', 0, Count);
end;

procedure TTestForkJoin.TestEachCoversRangeOnce;

const
  CLow = -1000;
  CHigh = 250000;

var
  Hits: array of LongInt;
  I: Integer;

begin
  SetLength(Hits, CHigh - CLow + 1);
  TForkJoin.Each(CLow, CHigh, procedure(aIndex: Int64)
    begin
    InterlockedIncrement(Hits[aIndex - CLow]);
    end);
  for I := 0 to High(Hits) do
    if Hits[I] <> 1 then
      Fail(Format('Index %d visited %d times', [I + CLow, Hits[I]]));
end;

procedure TTestForkJoin.TestEachEmptyAndSingle;

var
  Count: Int64;
  Last: Int64;

begin
  Count := 0;
  TForkJoin.Each(5, 4, procedure(aIndex: Int64) begin InterlockedIncrement64(Count); end);
  AssertEquals('Empty range', 0, Count);
  Last := -1;
  TForkJoin.Each(7, 7, procedure(aIndex: Int64) begin InterlockedIncrement64(Count); Last := aIndex; end);
  AssertEquals('Single index', 1, Count);
  AssertEquals(7, Last);
end;

procedure TTestForkJoin.TestEachGrain;

var
  Sum: Int64;

begin
  Sum := 0;
  TForkJoin.Each(1, 100000, procedure(aIndex: Int64) begin InterlockedExchangeAdd64(Sum, aIndex); end, 1);
  AssertEquals('Grain 1', Int64(100000) * 100001 div 2, Sum);
  Sum := 0;
  TForkJoin.Each(1, 100000, procedure(aIndex: Int64) begin InterlockedExchangeAdd64(Sum, aIndex); end, 1000000);
  AssertEquals('Grain above the range', Int64(100000) * 100001 div 2, Sum);
end;

procedure TTestForkJoin.TestEachException;

var
  Raised: Boolean;

begin
  Raised := False;
  try
    TForkJoin.Each(1, 100000, procedure(aIndex: Int64)
      begin
      if aIndex = 77777 then
        raise EForkJoinTest.Create('each');
      end);
  except
    on E: EForkJoinTest do
      Raised := True;
  end;
  AssertTrue('Each re-raises the exception of an iteration', Raised);
end;

procedure TTestForkJoin.TestJoinRunsBoth;

var
  A, B: Int64;

begin
  A := 0;
  B := 0;
  TForkJoin.Join(procedure begin A := Fib(25); end, procedure begin B := Fib(24); end);
  AssertEquals(75025, A);
  AssertEquals(46368, B);
end;

type
  TSpawnThread = class(TThread)
  protected
    procedure Execute; override;
  public
    Sum: Int64;
  end;

procedure TSpawnThread.Execute;

var
  Group: TTaskGroup;
  I: Integer;

begin
  Sum := 0;
  Group := TTaskGroup.Create;
  try
    for I := 1 to 20000 do
      Group.Spawn(I, procedure(aArg: Int64) begin InterlockedExchangeAdd64(Sum, aArg); end);
    Group.Wait;
  finally
    Group.Free;
  end;
end;

procedure TTestForkJoin.TestSpawnFromSeveralThreads;

var
  Threads: array[0..3] of TSpawnThread;
  I: Integer;

begin
  for I := 0 to High(Threads) do
    Threads[I] := TSpawnThread.Create(False);
  for I := 0 to High(Threads) do
    begin
    Threads[I].WaitFor;
    AssertEquals('Thread ' + IntToStr(I), Int64(20000) * 20001 div 2, Threads[I].Sum);
    Threads[I].Free;
    end;
end;

procedure TTestForkJoin.TestDestroyWaitsForTasks;

var
  Group: TTaskGroup;
  Count: Int64;
  I: Integer;

begin
  Count := 0;
  Group := TTaskGroup.Create;
  for I := 1 to 10000 do
    Group.Spawn(procedure begin Sleep(0); InterlockedIncrement64(Count); end);
  Group.Free;
  AssertEquals('Free waits for the tasks of the group', 10000, Count);
end;

procedure TTestForkJoin.TestWorkerCount;

begin
  AssertTrue(TForkJoin.WorkerCount >= 1);
end;

initialization
  RegisterTest(TTestForkJoin);
end.
