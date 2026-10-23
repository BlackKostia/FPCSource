program test_fiber_extended;

{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
{$ASYNCMODE FIBER}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, System.Threading, fclasync;

var
  Passed, Failed: Integer;
  Counter: Integer;

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

function DelayedVal(V: Integer): specialize IFuture<Integer>; async;
begin
  await TTask.Delay(10);
  Result := V;
end;

function AsyncCheckLess(Limit: Integer): specialize IFuture<Boolean>; async;
begin
  await TTask.Delay(5);
  Result := (Counter < Limit);
end;

function AsyncCheckDone: specialize IFuture<Boolean>; async;
begin
  await TTask.Delay(5);
  Result := (Counter >= 3);
end;

function AsyncCheckReach(Limit: Integer): specialize IFuture<Boolean>; async;
begin
  await TTask.Delay(5);
  Result := (Counter >= Limit);
end;

{ 1. Multiple awaits in assignment }
function TestMultipleAwaits: specialize IFuture<Integer>; async;
var
  X: Integer;
begin
  X := await DelayedVal(10) + await DelayedVal(20) + await DelayedVal(12);
  Result := X;
end;

{ 2. Complex expression with awaits }
function TestComplexExpr: specialize IFuture<Integer>; async;
begin
  Result := (await DelayedVal(5)) * (await DelayedVal(8)) + (await DelayedVal(2));
end;

{ 3. While await condition }
function TestWhileAwait: specialize IFuture<Integer>; async;
var
  Steps: Integer;
begin
  Counter := 0;
  Steps := 0;
  while await AsyncCheckLess(3) do
    begin
      Inc(Counter);
      Inc(Steps);
    end;
  Result := Steps;
end;

{ 4. While not await condition }
function TestWhileNotAwait: specialize IFuture<Integer>; async;
var
  Steps: Integer;
begin
  Counter := 0;
  Steps := 0;
  while not await AsyncCheckDone() do
    begin
      Inc(Counter);
      Inc(Steps);
    end;
  Result := Steps;
end;

{ 5. Repeat until await condition }
function TestRepeatUntilAwait: specialize IFuture<Integer>; async;
var
  Steps: Integer;
begin
  Counter := 0;
  Steps := 0;
  repeat
    Inc(Counter);
    Inc(Steps);
  until await AsyncCheckDone();
  Result := Steps;
end;

{ 6. Repeat until not await condition }
function TestRepeatUntilNotAwait: specialize IFuture<Integer>; async;
var
  Steps: Integer;
begin
  Counter := 0;
  Steps := 0;
  repeat
    Inc(Counter);
    Inc(Steps);
  until not await AsyncCheckLess(3);
  Result := Steps;
end;

{ 7. While await with continue and break }
function TestWhileBreakContinue: specialize IFuture<Integer>; async;
var
  Steps: Integer;
begin
  Counter := 0;
  Steps := 0;
  while await AsyncCheckLess(10) do
    begin
      Inc(Counter);
      if Counter = 2 then
        continue;
      if Counter = 4 then
        break;
      Inc(Steps);
    end;
  Result := Steps * 100 + Counter;
end;

{ 8. Repeat until await with continue and break }
function TestRepeatBreakContinue: specialize IFuture<Integer>; async;
var
  Steps: Integer;
begin
  Counter := 0;
  Steps := 0;
  repeat
    Inc(Counter);
    if Counter = 2 then
      continue;
    if Counter = 4 then
      break;
    Inc(Steps);
  until await AsyncCheckReach(10);
  Result := Steps * 100 + Counter;
end;

var
  F1, F2, F3, F4, F5, F6, F7, F8: specialize IFuture<Integer>;
begin
  Passed := 0;
  Failed := 0;
  Writeln('=== Testing Extended Fiber Await Operations ===');

  F1 := TestMultipleAwaits();
  Check('Multiple awaits: 10 + 20 + 12 = 42', F1.Value = 42);

  F2 := TestComplexExpr();
  Check('Complex expr awaits: 5 * 8 + 2 = 42', F2.Value = 42);

  F3 := TestWhileAwait();
  Check('While await condition executed 3 times', F3.Value = 3);

  F4 := TestWhileNotAwait();
  Check('While not await condition executed 3 times', F4.Value = 3);

  F5 := TestRepeatUntilAwait();
  Check('Repeat until await condition executed 3 times', F5.Value = 3);

  F6 := TestRepeatUntilNotAwait();
  Check('Repeat until not await condition executed 3 times', F6.Value = 3);

  F7 := TestWhileBreakContinue();
  Check('While await with break and continue: 204', F7.Value = 204);

  F8 := TestRepeatBreakContinue();
  Check('Repeat until await with break and continue: 204', F8.Value = 204);

  Writeln('===============================================');
  Writeln(Passed, ' passed, ', Failed, ' failed');
  if Failed <> 0 then
    Halt(1);
end.
