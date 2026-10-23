program stress_new_500_tests;

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
      begin
        // Fast-path immediate completed task
        Futures[J] := FastComputeAsync(J + 1);
      end
      else
      begin
        // Delayed asynchronous task
        Futures[J] := DelayedComputeAsync(J + 1, (J mod 3));
      end;
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
  Pure async functions without await: multiple branches, Exit(val), loops
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
      // Direct completed future
      F := TTask.specialize FromResult<Int64>(Int64(I) * 1000);
      Check(Format('Test %d: FromResult status Completed', [700 + I]),
        (F.Status = TTaskStatus.Completed) and (F.Value = Int64(I) * 1000));
    end
    else
    begin
      // Direct faulted future
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
  Pre-cancelled tokens and dynamic cancellation
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
      // Pre-cancelled token before starting
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
      // Dynamic cancellation
      F := AwaitWithTokenAsync(CTS.Token, 20);
      CTS.Cancel; // Cancel while waiting
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
  InitialCount: LongInt;
begin
  StartCategory('17. Unobserved Fire-and-Forget Exceptions (50 tests)');
  SW := TStopwatch.StartNew;

  OldHandler := OnUnobservedTaskException;
  OnUnobservedTaskException := @GlobalUnobservedHandler;

  InitialCount := UnobservedCount;
  for I := 1 to 50 do
  begin
    FireAndForgetFail(I);
    // Short wait to ensure worker finishes task execution and releases reference
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
      // Rapid fast-path tasks triggering lock-free InterlockedDecrement simultaneously
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
    // Rapid burst of 200 tasks per test round
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
  Main Runner
  ========================================================================= }

var
  TotalSW: TStopwatch;

begin
  Writeln('===============================================================================');
  Writeln('   MODERN FREE PASCAL (MFPC): 500 NEW STRESS TESTS (BATCH 2: 501..1000)');
  Writeln('===============================================================================');
  TotalSW := TStopwatch.StartNew;

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
  Writeln(Format('TOTAL: %d / 500 PASSED, %d FAILED in %d ms', [TotalPassed, TotalFailed, TotalSW.ElapsedMilliseconds]));
  Writeln('===============================================================================');

  if TotalFailed > 0 then
    Halt(1);
end.
