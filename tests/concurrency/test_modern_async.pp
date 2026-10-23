program test_modern_async;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
{$modeswitch arrowfunctions}
{$modeswitch implicitgenerics}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, Classes, SyncObjs,
  System.Threading,
  eventloop.types, eventloop.core,
  fcleventloop,
  fclasync;

var
  TestsPassed: Integer = 0;
  TestsFailed: Integer = 0;

procedure Check(const Msg: string; Condition: Boolean);
begin
  if Condition then
  begin
    Inc(TestsPassed);
    Writeln('  [PASS] ', Msg);
  end
  else
  begin
    Inc(TestsFailed);
    Writeln('  [FAIL] ', Msg);
  end;
end;

{ Helper: slow asynchronous future with simulated delay }
function DelayFuture(AMilliseconds: Integer; AValue: Integer): specialize IFuture<Integer>;
begin
  Result := TTask.Future(
    function: Integer
    begin
      Sleep(AMilliseconds);
      Result := AValue;
    end);
end;

{ --- 1. Async function returns immediately to caller (non-blocking call) --- }
function ComputeSlowlyAsync(AMs, AValue: Integer): specialize IFuture<Integer>; async;
var
  V: Integer;
begin
  V := await DelayFuture(AMs, AValue);
  Result := V * 2;
end;

procedure TestNonBlockingCaller;
var
  F: specialize IFuture<Integer>;
  T0, Took: QWord;
  Res: Integer;
begin
  Writeln('--- Test 1: Non-blocking Caller Return ---');
  T0 := GetTickCount64;
  F := ComputeSlowlyAsync(150, 21);
  Took := GetTickCount64 - T0;

  { The function must return immediately to the caller, long before the 150ms delay completes }
  Check('Call returns to caller immediately (< 50ms)', Took < 50);
  Check('Future is initially not completed', F.Status <> TTaskStatus.Completed);

  { Now read the result. }
  Res := F.Value;
  Check('Result from async function is correct (21 * 2 = 42)', Res = 42);
  Check('Future is now completed', F.Status = TTaskStatus.Completed);
end;

{ --- 2. Fire-and-forget async procedure --- }
var
  GBackgroundDone: Boolean = False;

procedure BackgroundTaskAsync(AMs: Integer); async;
begin
  await DelayFuture(AMs, 0);
  GBackgroundDone := True;
end;

procedure TestAsyncProcedure;
var
  T0, Took: QWord;
begin
  Writeln('--- Test 2: Fire-and-forget Async Procedure ---');
  GBackgroundDone := False;
  T0 := GetTickCount64;
  BackgroundTaskAsync(100);
  Took := GetTickCount64 - T0;

  Check('Async procedure call returns immediately (< 30ms)', Took < 30);
  Check('Background task not finished yet', not GBackgroundDone);

  { Wait for background task to complete }
  Sleep(150);
  Check('Background task finished asynchronously', GBackgroundDone);
end;

{ --- 3. High Concurrency without thread starvation (EventLoop + Fibers) --- }
procedure TestHighConcurrency;
const
  TotalTasks = 500;
var
  Loop: IEventLoop;
  CompletedCount: Integer;
  TotalSum: Int64;
  I: Integer;
  T0, Took: QWord;
begin
  Writeln('--- Test 3: High Concurrency (500 tasks on 1 Loop thread) ---');
  Loop := TEventLoop.Create(bkAuto);
  CompletedCount := 0;
  TotalSum := 0;

  T0 := GetTickCount64;

  { Spawn 500 concurrent async coroutines on ONE single event loop thread }
  for I := 1 to TotalTasks do
  begin
    SpawnAsync(
      procedure
      var
        Val: Integer;
      begin
        { If Value blocked, 500 tasks * 50ms = 25 seconds.
          Inside the fiber it suspends, so the tasks run concurrently. }
        Val := DelayFuture(50, 1).Value;
        InterlockedIncrement(CompletedCount);
        InterlockedExchangeAdd64(TotalSum, Val);
      end, Loop, 32 * 1024);
  end;

  { Pump event loop until all tasks complete }
  while (CompletedCount < TotalTasks) and (GetTickCount64 - T0 < 5000) do
    Loop.RunOnce(10);

  Took := GetTickCount64 - T0;

  Check('All 500 async tasks completed', CompletedCount = TotalTasks);
  Check('Total sum is 500', TotalSum = TotalTasks);
  Check('Completed rapidly without thread blocking (< 3000ms)', Took < 3000);
end;

{ --- 4. Multi-step Async Pipeline with Await --- }
function Step1Async(X: Integer): specialize IFuture<Integer>; async;
begin
  Result := await DelayFuture(30, X) + 10;
end;

function Step2Async(X: Integer): specialize IFuture<Integer>; async;
begin
  Result := await DelayFuture(30, X) * 3;
end;

function PipelineAsync(InputVal: Integer): specialize IFuture<Integer>; async;
var
  S1, S2: Integer;
begin
  S1 := await Step1Async(InputVal);  { Input + 10 }
  S2 := await Step2Async(S1);        { (Input + 10) * 3 }
  Result := S2;
end;

procedure TestAsyncPipeline;
var
  F: specialize IFuture<Integer>;
  Res: Integer;
begin
  Writeln('--- Test 4: Multi-Step Async Pipeline ---');
  { (5 + 10) * 3 = 45 }
  F := PipelineAsync(5);
  Res := F.Value;
  Check('Async pipeline result is 45', Res = 45);
end;

{ --- 5. Async Exception Handling (Propagation via Await) --- }
function FaultingAsync: specialize IFuture<Integer>; async;
begin
  Sleep(20);
  raise Exception.Create('Network connection timeout in async routine');
  Result := 0;
end;

procedure TestAsyncException;
var
  Caught: Boolean;
  ErrMsg: string;
begin
  Writeln('--- Test 5: Async Exception Propagation ---');
  Caught := False;
  ErrMsg := '';
  try
    FaultingAsync.Wait;
  except
    on E: EAggregateException do
    begin
      Caught := True;
      if E.Count > 0 then
        ErrMsg := E.InnerExceptions[0].Message
      else
        ErrMsg := E.Message;
    end;
    on E: Exception do
    begin
      Caught := True;
      ErrMsg := E.Message;
    end;
  end;

  Check('Exception was propagated and caught by caller try..except', Caught);
  Check('Exception message contains original error', Pos('Network connection timeout', ErrMsg) > 0);
end;

{ --- 6. Arrow Functions + Async Integration --- }
function ArrowAsyncAdd(A, B: Integer): specialize IFuture<Integer>; async;
begin
  Result := await DelayFuture(20, A) + await DelayFuture(20, B);
end;

procedure TestArrowAsync;
type
  TAddFunc = reference to function(X, Y: Integer): specialize IFuture<Integer>;
var
  AddLambda: TAddFunc;
  F: specialize IFuture<Integer>;
  Ans: Integer;
begin
  Writeln('--- Test 6: Arrow Functions and Async Synergy ---');
  AddLambda := (X: Integer, Y: Integer) => ArrowAsyncAdd(X, Y);
  F := AddLambda(100, 200);
  Ans := F.Value;
  Check('Arrow lambda in async routine produced 300', Ans = 300);
end;

begin
  Writeln('========================================');
  Writeln('   MODERN ASYNC / AWAIT TEST SUITE      ');
  Writeln('========================================');

  TestNonBlockingCaller;
  TestAsyncProcedure;
  TestHighConcurrency;
  TestAsyncPipeline;
  TestAsyncException;
  TestArrowAsync;

  Writeln('========================================');
  Writeln('Passed: ', TestsPassed, ', Failed: ', TestsFailed);
  if TestsFailed > 0 then
  begin
    Writeln('FAILURE: Some async tests failed!');
    Halt(1);
  end;
  Writeln('SUCCESS: All modern async/await tests passed successfully!');
end.
