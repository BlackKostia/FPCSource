program test_cancellation_await_fiber;

{$mode delphi}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
{$ASYNCMODE FIBER}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, Classes, System.Threading, System.Diagnostics,
  fclasync, async.fiber;

var
  PassedCount: Integer = 0;
  FailedCount: Integer = 0;
  GFinallyExecuted: Boolean = False;
  GProcExecutedAfterAwait: Boolean = False;

procedure Assert(ACondition: Boolean; const ADesc: string);
begin
  if ACondition then
  begin
    Inc(PassedCount);
    Writeln('  [PASS] ', ADesc);
  end
  else
  begin
    Inc(FailedCount);
    Writeln('  [FAIL] ', ADesc);
  end;
end;

procedure AsyncProcWithToken(const AToken: TCancellationToken); async;
begin
  await TTask.Delay(1000);
  GProcExecutedAfterAwait := True;
end;

function SlowFiberWithToken(const AToken: TCancellationToken): IFuture<Integer>; async;
begin
  await TTask.Delay(1000);
  Result := 42;
end;

function FiberWithFinally(const AToken: TCancellationToken): IFuture<Integer>; async;
begin
  try
    await TTask.Delay(1000);
    Result := 100;
  finally
    GFinallyExecuted := True;
  end;
end;

procedure TestCancelWhileAwaiting;
var
  CTS: TCancellationTokenSource;
  F: IFuture<Integer>;
  SW: TStopwatch;
  CaughtCancelled: Boolean;
begin
  CTS := TCancellationTokenSource.Create;
  SW := TStopwatch.StartNew;
  F := SlowFiberWithToken(CTS.Token);

  // Allow the fiber to start and suspend at await
  Sleep(30);

  // Cancel the token while await is suspended
  CTS.Cancel;

  CaughtCancelled := False;
  try
    F.Value;
  except
    on E: EOperationCancelled do
      CaughtCancelled := True;
    on E: Exception do
      Writeln('    Unexpected exception: ', E.ClassName, ': ', E.Message);
  end;

  SW.Stop;

  Assert(CaughtCancelled, 'Cancellation while suspended raised EOperationCancelled');
  Assert(SW.ElapsedMilliseconds < 500, Format('Interrupted quickly in %d ms (< 500 ms)', [SW.ElapsedMilliseconds]));
  Assert(F.Status = TTaskStatus.Canceled, 'Future status is Canceled');

  CTS.Free;
end;

procedure TestFinallyOnCancellation;
var
  CTS: TCancellationTokenSource;
  F: IFuture<Integer>;
  CaughtCancelled: Boolean;
begin
  GFinallyExecuted := False;
  CTS := TCancellationTokenSource.Create;
  F := FiberWithFinally(CTS.Token);

  Sleep(30);
  CTS.Cancel;

  CaughtCancelled := False;
  try
    F.Value;
  except
    on E: EOperationCancelled do
      CaughtCancelled := True;
  end;

  Assert(CaughtCancelled, 'Finally test raised EOperationCancelled');
  Assert(GFinallyExecuted, 'Finally block executed upon cancellation');

  CTS.Free;
end;

procedure TestAlreadyCancelledToken;
var
  CTS: TCancellationTokenSource;
  F: IFuture<Integer>;
  CaughtCancelled: Boolean;
begin
  CTS := TCancellationTokenSource.Create;
  CTS.Cancel; // Cancelled before calling async routine

  F := SlowFiberWithToken(CTS.Token);

  CaughtCancelled := False;
  try
    F.Value;
  except
    on E: EOperationCancelled do
      CaughtCancelled := True;
  end;

  Assert(CaughtCancelled, 'Already-cancelled token immediately raised EOperationCancelled');
  Assert(F.Status = TTaskStatus.Canceled, 'Already-cancelled future has Canceled status');

  CTS.Free;
end;

procedure TestProcedureCancellation;
var
  CTS: TCancellationTokenSource;
begin
  GProcExecutedAfterAwait := False;
  CTS := TCancellationTokenSource.Create;

  AsyncProcWithToken(CTS.Token);

  Sleep(30);
  CTS.Cancel;

  Sleep(100);

  Assert(not GProcExecutedAfterAwait, 'Async procedure did not continue past cancelled await');

  CTS.Free;
end;

begin
  Writeln('=== Testing CancellationToken in await (FIBER mode) ===');
  TestCancelWhileAwaiting;
  TestFinallyOnCancellation;
  TestAlreadyCancelledToken;
  TestProcedureCancellation;
  Writeln('=======================================================');
  Writeln(Format('%d passed, %d failed', [PassedCount, FailedCount]));
  if FailedCount > 0 then
    Halt(1);
end.
