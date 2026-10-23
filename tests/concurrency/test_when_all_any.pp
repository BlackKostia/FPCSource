program test_when_all_any;

{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
{$ASYNCMODE STATEMACHINE}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, System.Threading;

var
  Passed, Failed: Integer;

procedure Check(const Msg: string; Ok: Boolean);
begin
  if Ok then
    begin
      Inc(Passed);
      Writeln('  [PASS] ', Msg);
    end
  else
    begin
      Inc(Failed);
      Writeln('  [FAIL] ', Msg);
    end;
end;

function DelayedVal(V: Integer; DelayMs: Cardinal): specialize IFuture<Integer>; async;
begin
  await TTask.Delay(DelayMs);
  Result := V;
end;

{ 1. WhenAll with empty array }
function TestEmptyWhenAll: specialize IFuture<Boolean>; async;
var
  T: ITask;
begin
  T := TTask.WhenAll([]);
  await T;
  Result := (T.Status = TTaskStatus.Completed);
end;

{ 2. WhenAll with multiple tasks }
function TestWhenAllValues: specialize IFuture<Integer>; async;
var
  F1, F2, F3: specialize IFuture<Integer>;
begin
  F1 := DelayedVal(10, 30);
  F2 := DelayedVal(20, 10);
  F3 := DelayedVal(12, 20);

  await TTask.WhenAll([F1, F2, F3]);

  Result := F1.Value + F2.Value + F3.Value;
end;

{ 3. WhenAny picks the fastest task }
function TestWhenAnyFastest: specialize IFuture<Integer>; async;
var
  F_Slow, F_Fast, F_Medium: specialize IFuture<Integer>;
  Winner: ITask;
begin
  F_Slow := DelayedVal(1, 100);
  F_Fast := DelayedVal(2, 10);
  F_Medium := DelayedVal(3, 50);

  Winner := await TTask.WhenAny([F_Slow, F_Fast, F_Medium]);

  if Winner = (F_Fast as ITask) then
    Result := F_Fast.Value
  else
    Result := -1;
end;

{ 4. WhenAll propagates fault }
function FaultyTask: ITask; async;
begin
  await TTask.Delay(10);
  raise Exception.Create('Intentional failure');
end;

function TestWhenAllFault: specialize IFuture<Boolean>; async;
var
  T1, T2: ITask;
  Caught: Boolean;
begin
  T1 := TTask.Delay(20);
  T2 := FaultyTask();
  Caught := False;
  try
    await TTask.WhenAll([T1, T2]);
  except
    Caught := True;
  end;
  Result := Caught;
end;

var
  F1: specialize IFuture<Boolean>;
  F2, F3: specialize IFuture<Integer>;
  F4: specialize IFuture<Boolean>;
begin
  Passed := 0;
  Failed := 0;
  Writeln('=== Testing TTask.WhenAll and TTask.WhenAny ===');

  F1 := TestEmptyWhenAll();
  Check('WhenAll([]) completes immediately', F1.Value = True);

  F2 := TestWhenAllValues();
  Check('WhenAll([10, 20, 12]) completes all: 42', F2.Value = 42);

  F3 := TestWhenAnyFastest();
  Check('WhenAny picks fastest task: 2', F3.Value = 2);

  F4 := TestWhenAllFault();
  Check('WhenAll propagates fault to awaiter', F4.Value = True);

  Writeln('==============================================');
  Writeln(Passed, ' passed, ', Failed, ' failed');
  if Failed <> 0 then
    Halt(1);
end.
