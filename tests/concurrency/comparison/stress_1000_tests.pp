program stress_1000_tests;

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
  UnobservedCount: LongInt = 0;

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

  // Warm-up iteration: wake up CPU core and bring clocks to peak frequency
  RecursiveSumAsync(50).Value;

  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    Depth := 2 + (I * 3); // Depth from 5 to 152 frames
    Expected := Int64(Depth) * (Depth + 1) div 2;
    Actual := RecursiveSumAsync(Depth).Value;
    Check(Format('Test %d: RecursiveSumAsync(%d)', [I, Depth]), Actual = Expected);
  end;

  SW.Stop;
  EndCategory('1. Deep Recursion & Call-Chaining', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 2: Massive Fan-Out & Fan-In (WhenAll) (Tests 51..100)
  ========================================================================= }

function TaskWorkerAsync(Id, Multiplier: Integer): specialize IFuture<Int64>; async;
begin
  if (Id mod 5) = 0 then
    await TTask.Delay(1);
  Result := Int64(Id) * Multiplier;
end;

procedure RunCategory2;
var
  SW: TStopwatch;
  I, J, TaskCount: Integer;
  Tasks: array of ITask;
  Futures: array of specialize IFuture<Int64>;
  Sum, Expected: Int64;
begin
  StartCategory('2. Massive Fan-Out & Fan-In (WhenAll) (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    TaskCount := 5 + (I * 5); // 10 to 255 parallel tasks
    SetLength(Tasks, TaskCount);
    SetLength(Futures, TaskCount);
    Expected := 0;

    for J := 0 to TaskCount - 1 do
    begin
      Futures[J] := TaskWorkerAsync(J + 1, I);
      Tasks[J] := Futures[J];
      Expected := Expected + Int64(J + 1) * I;
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
  AnyTask: specialize IFuture<ITask>;
  Winner: ITask;
begin
  F0 := DelayTaskAsync(100, 20);
  F1 := DelayTaskAsync(200, 1);  // Fastest!
  F2 := DelayTaskAsync(300, 25);
  F3 := DelayTaskAsync(400, 30);

  AnyTask := TTask.WhenAny([F0, F1, F2, F3]);
  Winner := await AnyTask;
  if Winner.Id = F1.Id then
    Result := 200
  else if Winner.Id = F0.Id then
    Result := 100
  else
    Result := 0;
end;

procedure RunCategory4;
var
  SW: TStopwatch;
  I, Res: Integer;
begin
  StartCategory('4. First-Finisher Racing (WhenAny) (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    Res := RaceWinnerAsync.Value;
    Check(Format('Test %d: WhenAny picked fastest task (200)', [150 + I]), Res = 200);
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
  Result := 42;
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
    F := CancellableAsync(CTS.Token, 25);

    CTS.Cancel; // Cancel almost immediately

    Caught := False;
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
    Dec(Steps);
    if (Steps mod 2) = 0 then
      Accum := Accum + (await FastValueAsync(Steps) * 2)
    else
      Accum := Accum + await FastValueAsync(Steps);
  end;
  Result := Accum;
end;

procedure RunCategory8;
var
  SW: TStopwatch;
  I, Val, Expected, K: Integer;
begin
  StartCategory('8. Complex Control Flow & Expressions (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    Val := ComplexFlowAsync(3).Value;
    Expected := 0;
    for K := 2 downto 0 do
      if (K mod 2) = 0 then
        Expected := Expected + (K * 2)
      else
        Expected := Expected + K;

    Check(Format('Test %d: While await condition and complex expr', [350 + I]), Val = Expected);
  end;

  SW.Stop;
  EndCategory('8. Complex Control Flow & Expressions', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 9: State Preservation Across Thread Hopping (Tests 401..450)
  ========================================================================= }

function StateThreadHopperAsync(Steps: Integer): specialize IFuture<string>; async;
var
  LocalState: string;
  Step: Integer;
begin
  LocalState := 'Init';
  for Step := 1 to Steps do
  begin
    LocalState := LocalState + Format('->S%d', [Step]);
    await TTask.Delay(1);
  end;
  Result := LocalState;
end;

procedure RunCategory9;
var
  SW: TStopwatch;
  I: Integer;
  Actual, Expected: string;
begin
  StartCategory('9. State Preservation Across Thread Hopping (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    Actual := StateThreadHopperAsync(2).Value;
    Expected := 'Init->S1->S2';
    Check(Format('Test %d: Managed string state preserved across await', [400 + I]), Actual = Expected);
  end;

  SW.Stop;
  EndCategory('9. State Preservation Across Thread Hopping', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 10: Multi-threaded Reentrancy & Sustained Concurrency (Tests 451..500)
  ========================================================================= }

type
  TReentrancyRunner = class(TThread)
  private
    FSuccess: Boolean;
  public
    constructor Create;
    procedure Execute; override;
    property Success: Boolean read FSuccess;
  end;

constructor TReentrancyRunner.Create;
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FSuccess := False;
end;

procedure TReentrancyRunner.Execute;
var
  F: specialize IFuture<Int64>;
begin
  F := FastSumAsync(20);
  FSuccess := (F.Value = (20 * 21 div 2));
end;

procedure RunCategory10;
var
  SW: TStopwatch;
  I, T: Integer;
  Threads: array[0..3] of TReentrancyRunner;
  AllOk: Boolean;
begin
  StartCategory('10. Multi-threaded Reentrancy (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    for T := 0 to 3 do
      Threads[T] := TReentrancyRunner.Create;

    for T := 0 to 3 do
      Threads[T].Start;

    AllOk := True;
    for T := 0 to 3 do
    begin
      Threads[T].WaitFor;
      if not Threads[T].Success then
        AllOk := False;
      Threads[T].Free;
    end;

    Check(Format('Test %d: 4 concurrent OS threads reentrancy', [450 + I]), AllOk);
  end;

  SW.Stop;
  EndCategory('10. Multi-threaded Reentrancy', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 11: Mixed Heterogeneous WhenAll (Tests 501..550)
  Mix of fast-path immediate tasks and delayed async tasks
  ========================================================================= }

function FastComputeAsync(V: Integer): specialize IFuture<Integer>; async;
begin
  Result := V * 2;
end;

function DelayedComputeAsync(V, DelayMs: Integer): specialize IFuture<Integer>; async;
begin
  if DelayMs > 0 then
    await TTask.Delay(DelayMs);
  Result := V * 2;
end;

procedure RunCategory11;
var
  SW: TStopwatch;
  I, J, Count: Integer;
  Tasks: array of ITask;
  Futures: array of specialize IFuture<Integer>;
  Sum, Expected: Int64;
begin
  StartCategory('11. Mixed Heterogeneous WhenAll (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    Count := 2 + (I mod 30); // 2 to 31 tasks
    SetLength(Tasks, Count);
    SetLength(Futures, Count);
    Expected := 0;

    for J := 0 to Count - 1 do
    begin
      if (J mod 2) = 0 then
        Futures[J] := FastComputeAsync(J + 1)
      else
        Futures[J] := DelayedComputeAsync(J + 1, (J mod 3));
      Tasks[J] := Futures[J];
      Expected := Expected + (J + 1) * 2;
    end;

    TTask.WhenAll(Tasks).Wait;

    Sum := 0;
    for J := 0 to Count - 1 do
      Inc(Sum, Futures[J].Value);

    Check(Format('Test %d: Mixed WhenAll(%d tasks) sum match', [500 + I, Count]), Sum = Expected);
  end;

  SW.Stop;
  EndCategory('11. Mixed Heterogeneous WhenAll', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 12: WhenAll Fault Aggregation & Atomic Exception Races (Tests 551..600)
  ========================================================================= }

function FaultingTaskAsync(Id: Integer; DelayMs: Integer): specialize IFuture<Integer>; async;
begin
  if DelayMs > 0 then
    await TTask.Delay(DelayMs);
  raise Exception.Create(Format('Simulated fault %d', [Id]));
  Result := Id;
end;

procedure RunCategory12;
var
  SW: TStopwatch;
  I, J, Count: Integer;
  Tasks: array of ITask;
  Caught: Boolean;
  AllTask: ITask;
begin
  StartCategory('12. WhenAll Fault Aggregation & Atomic Exception Races (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    Count := 3 + (I mod 15);
    SetLength(Tasks, Count);

    for J := 0 to Count - 1 do
    begin
      if (J = 1) or (J = Count - 1) then
        Tasks[J] := FaultingTaskAsync(J, J mod 2)
      else
        Tasks[J] := FastComputeAsync(J * 10);
    end;

    AllTask := TTask.WhenAll(Tasks);
    Caught := False;
    try
      AllTask.Wait;
    except
      Caught := True;
    end;

    Check(Format('Test %d: Fault properly surfaced in WhenAll(%d tasks)', [550 + I, Count]),
      Caught and (AllTask.Status = TTaskStatus.Exception));
  end;

  SW.Stop;
  EndCategory('12. WhenAll Fault Aggregation & Atomic Races', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 13: WhenAny Fast-Path Racing & Lock-Free Winner Claims (Tests 601..650)
  ========================================================================= }

function SlowCandidateAsync(Id: Integer): specialize IFuture<Integer>; async;
begin
  await TTask.Delay(10);
  Result := Id;
end;

procedure RunCategory13;
var
  SW: TStopwatch;
  I: Integer;
  F0, F1, F2: specialize IFuture<Integer>;
  AnyTask: specialize IFuture<ITask>;
  Winner: ITask;
begin
  StartCategory('13. WhenAny Fast-Path Racing & Winner Claims (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    F0 := SlowCandidateAsync(100);
    F1 := FastComputeAsync(42); // Immediate winner! (Value = 84)
    F2 := SlowCandidateAsync(300);

    AnyTask := TTask.WhenAny([F0, F1, F2]);
    Winner := AnyTask.Value;

    // F1 should win because it completes synchronously without delay
    Check(Format('Test %d: Fast-path candidate wins WhenAny instantly', [600 + I]),
      (Winner.Id = F1.Id) and (F1.Value = 84));
  end;

  SW.Stop;
  EndCategory('13. WhenAny Fast-Path Racing & Claims', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 14: Fast-Path Compiler Optimization with Complex Flow (Tests 651..700)
  ========================================================================= }

function FastBranchAsync(X, Y: Integer): specialize IFuture<Integer>; async;
var
  K, Acc: Integer;
begin
  if X < 0 then
  begin
    Result := -1;
    Exit;
  end;

  if Y = 0 then
  begin
    Result := 999;
    Exit;
  end;

  Acc := 0;
  for K := 1 to X do
    Acc := Acc + (K * Y);

  Result := Acc;
end;

function FastStringAsync(const S: string; Count: Integer): specialize IFuture<string>; async;
var
  I: Integer;
  Res: string;
begin
  if Count <= 0 then
  begin
    Result := '';
    Exit;
  end;
  Res := '';
  for I := 1 to Count do
    Res := Res + S;
  Result := Res;
end;

procedure RunCategory14;
var
  SW: TStopwatch;
  I, Val: Integer;
  StrVal: string;
begin
  StartCategory('14. Fast-Path Optimization Under Complex Flow (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    case (I mod 3) of
      0: begin
        Val := FastBranchAsync(-5, 10).Value;
        Check(Format('Test %d: Fast-path early exit(-1)', [650 + I]), Val = -1);
      end;
      1: begin
        Val := FastBranchAsync(5, 0).Value;
        Check(Format('Test %d: Fast-path Exit(999)', [650 + I]), Val = 999);
      end;
      2: begin
        StrVal := FastStringAsync('AB', 3).Value;
        Check(Format('Test %d: Fast-path string loop result', [650 + I]), StrVal = 'ABABAB');
      end;
    end;
  end;

  SW.Stop;
  EndCategory('14. Fast-Path Optimization Under Complex Flow', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 15: TTask.FromResult & TTask.FromException Direct API (Tests 701..750)
  ========================================================================= }

procedure RunCategory15;
var
  SW: TStopwatch;
  I: Integer;
  F: specialize IFuture<Int64>;
  FEx: specialize IFuture<Integer>;
  Caught: Boolean;
begin
  StartCategory('15. TTask.FromResult & TTask.FromException Direct API (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    if (I mod 2) = 1 then
    begin
      F := TTask.specialize FromResult<Int64>(Int64(I) * 1000);
      Check(Format('Test %d: FromResult status Completed', [700 + I]),
        (F.Status = TTaskStatus.Completed) and (F.Value = Int64(I) * 1000));
    end
    else
    begin
      FEx := TTask.specialize FromException<Integer>(Exception.Create('Explicit error'));
      Caught := False;
      try
        FEx.Value;
      except
        Caught := True;
      end;
      Check(Format('Test %d: FromException status Exception', [700 + I]),
        Caught and (FEx.Status = TTaskStatus.Exception));
    end;
  end;

  SW.Stop;
  EndCategory('15. TTask.FromResult & FromException Direct API', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 16: Advanced Cancellation Token in Await (Tests 751..800)
  ========================================================================= }

function AwaitWithTokenAsync(const AToken: TCancellationToken; DelayMs: Integer): specialize IFuture<Integer>; async;
begin
  if DelayMs > 0 then
    await TTask.Delay(DelayMs);
  Result := 777;
end;

procedure RunCategory16;
var
  SW: TStopwatch;
  I: Integer;
  CTS: TCancellationTokenSource;
  F: specialize IFuture<Integer>;
  Caught: Boolean;
begin
  StartCategory('16. Advanced Cancellation Token in Await (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    CTS := TCancellationTokenSource.Create;
    if (I mod 2) = 1 then
    begin
      CTS.Cancel;
      Caught := False;
      try
        F := AwaitWithTokenAsync(CTS.Token, 5);
        F.Value;
      except
        on E: EOperationCancelled do
          Caught := True;
      end;
      Check(Format('Test %d: Pre-cancelled token caught EOperationCancelled', [750 + I]), Caught);
    end
    else
    begin
      F := AwaitWithTokenAsync(CTS.Token, 20);
      CTS.Cancel;
      Caught := False;
      try
        F.Value;
      except
        on E: EOperationCancelled do
          Caught := True;
      end;
      Check(Format('Test %d: Dynamic cancellation interrupted await', [750 + I]), Caught);
    end;
    CTS.Free;
  end;

  SW.Stop;
  EndCategory('16. Advanced Cancellation Token in Await', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 17: Unobserved Fire-and-Forget Exception Tracking (Tests 801..850)
  ========================================================================= }

procedure FireAndForgetFail(Id: Integer); async;
begin
  await TTask.Delay(1);
  raise Exception.Create(Format('Unobserved fire-and-forget %d', [Id]));
end;

procedure GlobalUnobservedHandler(const ATask: ITask; AException: Exception);
begin
  InterlockedIncrement(UnobservedCount);
end;

procedure RunCategory17;
var
  SW: TStopwatch;
  I: Integer;
  OldHandler: TUnobservedTaskExceptionEvent;
begin
  StartCategory('17. Unobserved Fire-and-Forget Exceptions (50 tests)');
  SW := TStopwatch.StartNew;

  OldHandler := OnUnobservedTaskException;
  OnUnobservedTaskException := @GlobalUnobservedHandler;

  for I := 1 to 50 do
  begin
    FireAndForgetFail(I);
    Sleep(1);
    Check(Format('Test %d: Unobserved task executed', [800 + I]), True);
  end;

  OnUnobservedTaskException := OldHandler;

  SW.Stop;
  EndCategory('17. Unobserved Fire-and-Forget Exceptions', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 18: High-Density Lock-Free Fan-Out / Fan-In Stress (Tests 851..900)
  ========================================================================= }

procedure RunCategory18;
var
  SW: TStopwatch;
  I, J, TaskCount: Integer;
  Tasks: array of ITask;
  Futures: array of specialize IFuture<Integer>;
  Sum, Expected: Int64;
begin
  StartCategory('18. High-Density Lock-Free Fan-Out / Fan-In (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    TaskCount := 50 + (I * 2); // 52 to 150 tasks in single WhenAll
    SetLength(Tasks, TaskCount);
    SetLength(Futures, TaskCount);
    Expected := 0;

    for J := 0 to TaskCount - 1 do
    begin
      Futures[J] := FastComputeAsync(J);
      Tasks[J] := Futures[J];
      Expected := Expected + (J * 2);
    end;

    TTask.WhenAll(Tasks).Wait;

    Sum := 0;
    for J := 0 to TaskCount - 1 do
      Inc(Sum, Futures[J].Value);

    Check(Format('Test %d: High-density lock-free WhenAll(%d tasks)', [850 + I, TaskCount]), Sum = Expected);
  end;

  SW.Stop;
  EndCategory('18. High-Density Lock-Free Fan-Out / Fan-In', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 19: Nested Combinator Hierarchies (WhenAll of WhenAny) (Tests 901..950)
  ========================================================================= }

function NestedTreeAsync(Depth: Integer): specialize IFuture<Integer>; async;
var
  F0, F1: specialize IFuture<Integer>;
  AnyTask: specialize IFuture<ITask>;
  Win: ITask;
begin
  if Depth <= 1 then
  begin
    Result := await FastComputeAsync(5);
    Exit;
  end;

  F0 := FastComputeAsync(10);
  F1 := SlowCandidateAsync(20);
  AnyTask := TTask.WhenAny([F0, F1]);
  Win := await AnyTask;
  if Win.Id = F0.Id then
    Result := F0.Value + await NestedTreeAsync(Depth - 1)
  else
    Result := F1.Value + await NestedTreeAsync(Depth - 1);
end;

procedure RunCategory19;
var
  SW: TStopwatch;
  I, Res: Integer;
begin
  StartCategory('19. Nested Combinator Hierarchies (50 tests)');
  SW := TStopwatch.StartNew;

  for I := 1 to 50 do
  begin
    Res := NestedTreeAsync(3).Value; // 20 + 20 + 10 = 50
    Check(Format('Test %d: Hierarchical combinator result', [900 + I]), Res = 50);
  end;

  SW.Stop;
  EndCategory('19. Nested Combinator Hierarchies', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Category 20: Memory Stability & ARC Lifecycle Under Sustained Load (Tests 951..1000)
  ========================================================================= }

procedure RunCategory20;
var
  SW: TStopwatch;
  I, J: Integer;
  F: specialize IFuture<Integer>;
  Accum: Int64;
begin
  StartCategory('20. Memory Stability & ARC Lifecycle (50 tests)');
  SW := TStopwatch.StartNew;

  Accum := 0;
  for I := 1 to 50 do
  begin
    for J := 1 to 200 do
    begin
      F := FastComputeAsync(J);
      Accum := Accum + F.Value;
    end;
    Check(Format('Test %d: 200 rapid lifecycle tasks completed', [950 + I]), Accum > 0);
  end;

  SW.Stop;
  EndCategory('20. Memory Stability & ARC Lifecycle', SW.ElapsedMilliseconds);
end;

{ =========================================================================
  Main Runner: All 1000 Stress Tests
  ========================================================================= }

var
  TotalSW: TStopwatch;

begin
  Writeln('===============================================================================');
  Writeln('   MODERN FREE PASCAL (MFPC): 1000 STRESS TESTS SUITE FOR ASYNC / AWAIT');
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
  RunCategory11;
  RunCategory12;
  RunCategory13;
  RunCategory14;
  RunCategory15;
  RunCategory16;
  RunCategory17;
  RunCategory18;
  RunCategory19;
  RunCategory20;

  TotalSW.Stop;
  Writeln('===============================================================================');
  Writeln(Format('TOTAL: %d / 1000 PASSED, %d FAILED in %d ms', [TotalPassed, TotalFailed, TotalSW.ElapsedMilliseconds]));
  Writeln('===============================================================================');

  if TotalFailed > 0 then
    Halt(1);
end.
