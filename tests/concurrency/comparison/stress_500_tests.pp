program stress_500_tests;

{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
{$ASYNCMODE STATEMACHINE}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, Classes, System.Threading, System.Diagnostics;

var
  TotalPassed: Integer = 0;
  TotalFailed: Integer = 0;
  CategoryPassed: Integer = 0;
  CategoryFailed: Integer = 0;
  CleanupCounter: Integer = 0;

procedure Check(const ADesc: string; AOk: Boolean);
begin
  if AOk then
  begin
    Inc(TotalPassed);
    Inc(CategoryPassed);
  end
  else
  begin
    Inc(TotalFailed);
    Inc(CategoryFailed);
    Writeln('  [FAIL] ', ADesc);
  end;
end;

procedure StartCategory(const AName: string);
begin
  CategoryPassed := 0;
  CategoryFailed := 0;
  Writeln('--- [Category] ', AName, ' ---');
end;

procedure EndCategory(const AName: string; AElapsedMs: Int64);
begin
  Writeln(Format('    Result: %d/50 passed (%d failed) in %d ms', [CategoryPassed, CategoryFailed, AElapsedMs]));
end;

{ =========================================================================
  Category 1: Deep Recursion & Call-Chaining (Tests 1..50)
  ========================================================================= }

function RecursiveSumAsync(N: Integer): specialize IFuture<Int64>; async;
var
  Sub: Int64;
begin
  if N <= 1 then
  begin
    Result := N;
    Exit;
  end;
  Sub := await RecursiveSumAsync(N - 1);
  Result := N + Sub;
end;

procedure RunCategory1;
var
  SW: TStopwatch;
  I: Integer;
  Expected, Actual: Int64;
  Depth: Integer;
begin
  StartCategory('1. Deep Recursion & Call-Chaining (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    Depth := I * 4; // depths 4, 8, ..., 200
    Expected := Int64(Depth) * (Depth + 1) div 2;
    Actual := RecursiveSumAsync(Depth).Value;
    Check(Format('Test %d: Recursion depth %d', [I, Depth]), Actual = Expected);
  end;

  SW.Stop;
  EndCategory('1. Deep Recursion', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 2: Massive Fan-Out & Fan-In (WhenAll) (Tests 51..100)
  ========================================================================= }

function WorkerTaskAsync(Id, Multiplier: Integer): specialize IFuture<Integer>; async;
begin
  await TTask.Delay(1);
  Result := Id * Multiplier;
end;

procedure RunCategory2;
var
  SW: TStopwatch;
  I, J, TaskCount, Sum, Expected: Integer;
  Tasks: array of ITask;
  Futures: array of specialize IFuture<Integer>;
begin
  StartCategory('2. Massive Fan-Out & Fan-In (WhenAll) (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    TaskCount := 5 + (I * 5); // 10 to 255 tasks
    SetLength(Tasks, TaskCount);
    SetLength(Futures, TaskCount);
    Expected := 0;

    for J := 0 to TaskCount - 1 do
    begin
      Futures[J] := WorkerTaskAsync(J + 1, 2);
      Tasks[J] := Futures[J];
      Inc(Expected, (J + 1) * 2);
    end;

    TTask.WhenAll(Tasks).Wait;

    Sum := 0;
    for J := 0 to TaskCount - 1 do
      Inc(Sum, Futures[J].Value);

    Check(Format('Test %d: Fan-Out WhenAll(%d tasks)', [50 + I, TaskCount]), Sum = Expected);
  end;

  SW.Stop;
  EndCategory('2. Massive Fan-Out & Fan-In', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 3: Fast-Path Synchronous Awaits (Tests 101..150)
  ========================================================================= }

function FastValueAsync(V: Integer): specialize IFuture<Integer>; async;
begin
  Result := V;
end;

function FastSumAsync(Count: Integer): specialize IFuture<Int64>; async;
var
  K: Integer;
  S: Int64;
begin
  S := 0;
  for K := 1 to Count do
  begin
    S := S + await FastValueAsync(K);
  end;
  Result := S;
end;

procedure RunCategory3;
var
  SW: TStopwatch;
  I, N: Integer;
  Actual, Expected: Int64;
begin
  StartCategory('3. Fast-Path Synchronous Awaits (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    N := I * 50; // 50 to 2500 fast-path awaits
    Expected := Int64(N) * (N + 1) div 2;
    Actual := FastSumAsync(N).Value;
    Check(Format('Test %d: Fast-path %d awaits', [100 + I, N]), Actual = Expected);
  end;

  SW.Stop;
  EndCategory('3. Fast-Path Synchronous Awaits', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 4: First-Finisher Racing (WhenAny) (Tests 151..200)
  ========================================================================= }

function DelayTaskAsync(Id, DelayMs: Integer): specialize IFuture<Integer>; async;
begin
  await TTask.Delay(DelayMs);
  Result := Id;
end;

function RaceWinnerAsync: specialize IFuture<Integer>; async;
var
  F0, F1, F2, F3: specialize IFuture<Integer>;
  Winner: ITask;
begin
  F0 := DelayTaskAsync(100, 20);
  F1 := DelayTaskAsync(200, 1);  // Fastest!
  F2 := DelayTaskAsync(300, 25);
  F3 := DelayTaskAsync(400, 30);

  Winner := await TTask.WhenAny([F0, F1, F2, F3]);
  if Winner = (F1 as ITask) then
    Result := F1.Value
  else
    Result := -1;
end;

procedure RunCategory4;
var
  SW: TStopwatch;
  I, WinnerId: Integer;
begin
  StartCategory('4. First-Finisher Racing (WhenAny) (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    WinnerId := RaceWinnerAsync.Value;
    Check(Format('Test %d: WhenAny winner is fastest', [150 + I]), WinnerId = 200);
  end;

  SW.Stop;
  EndCategory('4. First-Finisher Racing', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 5: Cooperative Cancellation (CancellationToken) (Tests 201..250)
  ========================================================================= }

function CancellableAsync(const AToken: TCancellationToken; DelayMs: Integer): specialize IFuture<Integer>; async;
begin
  await TTask.Delay(DelayMs);
  Result := 777;
end;

procedure RunCategory5;
var
  SW: TStopwatch;
  I: Integer;
  CTS: TCancellationTokenSource;
  F: specialize IFuture<Integer>;
  Caught: Boolean;
begin
  StartCategory('5. Cooperative Cancellation (CancellationToken) (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    CTS := TCancellationTokenSource.Create;
    Caught := False;

    if I <= 15 then
    begin
      // Pre-cancelled
      CTS.Cancel;
      F := CancellableAsync(CTS.Token, 500);
    end
    else
    begin
      // Cancel during active await
      F := CancellableAsync(CTS.Token, 500);
      Sleep(2);
      CTS.Cancel;
    end;

    try
      F.Value;
    except
      on E: EOperationCancelled do
        Caught := True;
    end;

    Check(Format('Test %d: Cancellation caught and status Canceled', [200 + I]),
      Caught and (F.Status = TTaskStatus.Canceled));
    CTS.Free;
  end;

  SW.Stop;
  EndCategory('5. Cooperative Cancellation', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 6: Exception Propagation & Handling (Tests 251..300)
  ========================================================================= }

function FaultingChainAsync(Depth: Integer): specialize IFuture<Integer>; async;
begin
  if Depth <= 0 then
    raise Exception.Create('Intentional failure');
  Result := await FaultingChainAsync(Depth - 1) + 1;
end;

function RecoveringAsync(Depth: Integer): specialize IFuture<Integer>; async;
begin
  try
    Result := await FaultingChainAsync(Depth);
  except
    Result := 999; // Recovered!
  end;
end;

procedure RunCategory6;
var
  SW: TStopwatch;
  I, Val: Integer;
  F: specialize IFuture<Integer>;
  Caught: Boolean;
begin
  StartCategory('6. Exception Propagation & Handling (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    if (I mod 2) = 1 then
    begin
      // Propagation test
      F := FaultingChainAsync(I mod 10);
      Caught := False;
      try
        F.Value;
      except
        on E: Exception do
        begin
          if E is EAggregateException then
            Caught := (EAggregateException(E).Count > 0) and
                      (Pos('Intentional failure', EAggregateException(E).InnerExceptions[0].Message) > 0)
          else
            Caught := Pos('Intentional failure', E.Message) > 0;
        end;
      end;
      Check(Format('Test %d: Exception propagated through %d frames', [250 + I, I mod 10]), Caught);
    end
    else
    begin
      // Recovery test
      Val := RecoveringAsync(I mod 10).Value;
      Check(Format('Test %d: Exception recovered with fallback', [250 + I]), Val = 999);
    end;
  end;

  SW.Stop;
  EndCategory('6. Exception Propagation & Handling', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 7: Deterministic Cleanup (try ... finally) (Tests 301..350)
  ========================================================================= }

function ResourceCleaningAsync(Fail: Boolean): specialize IFuture<Integer>; async;
begin
  InterlockedIncrement(CleanupCounter);
  try
    await TTask.Delay(1);
    if Fail then
      raise Exception.Create('Resource error');
    Result := 123;
  finally
    InterlockedDecrement(CleanupCounter);
  end;
end;

procedure RunCategory7;
var
  SW: TStopwatch;
  I: Integer;
  F: specialize IFuture<Integer>;
begin
  StartCategory('7. Deterministic Cleanup (try ... finally) (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    F := ResourceCleaningAsync((I mod 2) = 0);
    try
      F.Value;
    except
      // ignore expected exception
    end;
    Check(Format('Test %d: Finally block executed (counter balanced)', [300 + I]), CleanupCounter = 0);
  end;

  SW.Stop;
  EndCategory('7. Deterministic Cleanup', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 8: Complex Control Flow & Expressions (Tests 351..400)
  ========================================================================= }

function BoolConditionAsync(StepsLeft: Integer): specialize IFuture<Boolean>; async;
begin
  await TTask.Delay(1);
  Result := (StepsLeft > 0);
end;

function ComplexFlowAsync(Count: Integer): specialize IFuture<Integer>; async;
var
  Accum: Integer;
  Steps: Integer;
begin
  Accum := 0;
  Steps := Count;
  while await BoolConditionAsync(Steps) do
  begin
    Accum := Accum + (await FastValueAsync(2)) + (await FastValueAsync(3));
    Dec(Steps);
  end;
  Result := Accum;
end;

procedure RunCategory8;
var
  SW: TStopwatch;
  I, N, Actual, Expected: Integer;
begin
  StartCategory('8. Complex Control Flow & Expressions (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    N := (I mod 5) + 1; // 1 to 5 loop steps
    Expected := N * 5;  // each step adds 2 + 3 = 5
    Actual := ComplexFlowAsync(N).Value;
    Check(Format('Test %d: while await Condition() with %d steps', [350 + I, N]), Actual = Expected);
  end;

  SW.Stop;
  EndCategory('8. Complex Control Flow & Expressions', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 9: State Preservation Across Thread Hopping (Tests 401..450)
  ========================================================================= }

function StateMutationAsync(InitialVal: Integer; StepCount: Integer): specialize IFuture<Integer>; async;
var
  K, CurrentVal: Integer;
  S: string;
begin
  CurrentVal := InitialVal;
  S := 'State:';
  for K := 1 to StepCount do
  begin
    await TTask.Delay(1);
    CurrentVal := CurrentVal + K;
    S := S + IntToStr(K) + ',';
  end;
  // Ensure string state survived multiple hops
  if Length(S) > 6 then
    Result := CurrentVal
  else
    Result := -1;
end;

procedure RunCategory9;
var
  SW: TStopwatch;
  I, Steps, Expected, Actual, K: Integer;
begin
  StartCategory('9. State Preservation Across Thread Hopping (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    Steps := (I mod 4) + 1; // 1..4 hops
    Expected := 100;
    for K := 1 to Steps do Expected := Expected + K;

    Actual := StateMutationAsync(100, Steps).Value;
    Check(Format('Test %d: Preserved mutated locals across %d thread hops', [400 + I, Steps]), Actual = Expected);
  end;

  SW.Stop;
  EndCategory('9. State Preservation Across Thread Hopping', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 10: Multi-threaded Reentrancy & Sustained Concurrency (Tests 451..500)
  ========================================================================= }

function ComputeSquareAsync(V: Integer): specialize IFuture<Integer>; async;
begin
  await TTask.Delay(1);
  Result := V * V;
end;

procedure RunCategory10;
var
  SW: TStopwatch;
  I, J, ConcurrentCallers: Integer;
  Tasks: array of ITask;
  Futures: array of specialize IFuture<Integer>;
  AllCorrect: Boolean;
begin
  StartCategory('10. Multi-threaded Reentrancy & Sustained Concurrency (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    ConcurrentCallers := 16;
    SetLength(Tasks, ConcurrentCallers);
    SetLength(Futures, ConcurrentCallers);

    for J := 0 to ConcurrentCallers - 1 do
    begin
      Futures[J] := ComputeSquareAsync(J + 1);
      Tasks[J] := Futures[J];
    end;

    TTask.WhenAll(Tasks).Wait;

    AllCorrect := True;
    for J := 0 to ConcurrentCallers - 1 do
      if Futures[J].Value <> (J + 1) * (J + 1) then
        AllCorrect := False;

    Check(Format('Test %d: 16 concurrent reentrant callers', [450 + I]), AllCorrect);
  end;

  SW.Stop;
  EndCategory('10. Multi-threaded Reentrancy', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Main Test Suite Runner
  ========================================================================= }

var
  TotalSW: TStopwatch;

begin
  Writeln('===============================================================================');
  Writeln('   MODERN FREE PASCAL (MFPC): 500 STRESS TESTS SUITE FOR ASYNC / AWAIT');
  Writeln('===============================================================================');
  TotalSW := TStopwatch.StartNew;

  RunCategory1;
  RunCategory2;
  RunCategory3;
  RunCategory4;
  RunCategory5;
  RunCategory6;
  RunCategory7;
  RunCategory8;
  RunCategory9;
  RunCategory10;

  TotalSW.Stop;
  Writeln('===============================================================================');
  Writeln(Format('TOTAL: %d / 500 PASSED, %d FAILED in %d ms', [TotalPassed, TotalFailed, TotalSW.ElapsedMilliseconds]));
  Writeln('===============================================================================');

  if TotalFailed > 0 then
    Halt(1);
end.
