{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
{$modeswitch implicitgenerics}

program test_mode_switch;

uses
  {$ifdef unix}cthreads,{$endif}
  sysutils,
  fclasync,
  system.threading;

var
  Passed, Failed: Integer;

procedure Check(const Desc: string; Condition: Boolean);
begin
  if Condition then
  begin
    Inc(Passed);
    Writeln('  [PASS] ', Desc);
  end
  else
  begin
    Inc(Failed);
    Writeln('  [FAIL] ', Desc);
  end;
end;

function DelayFuture(AMilliseconds: Integer; AValue: Integer): specialize IFuture<Integer>;
begin
  Result := TTask.Future(
    function: Integer
    begin
      Sleep(AMilliseconds);
      Result := AValue;
    end);
end;

{ --- Identical routine body --- }
{$IFDEF USE_STATEMACHINE}
{$ASYNCMODE STATEMACHINE}
{$ELSE}
{$ASYNCMODE FIBER}
{$ENDIF}

function ComputeUser(id: Integer): specialize IFuture<Integer>; async;
begin
  { Result has type Integer in BOTH modes! }
  Result := await DelayFuture(30, id * 2);
end;

function ComputePipeline(baseVal: Integer): specialize IFuture<Integer>; async;
var
  a, b: Integer;
begin
  a := await DelayFuture(20, baseVal + 10);
  b := await DelayFuture(20, a * 2);
  Result := b;
end;

function DirectResult(x: Integer): specialize IFuture<Integer>; async;
begin
  Result := x * 10;
end;

var
  ProcDone: Integer = 0;

procedure BackgroundTask(val: Integer); async;
begin
  await DelayFuture(20, 0);
  ProcDone := val;
end;

procedure RunTests;
var
  F1, F2, F3: specialize IFuture<Integer>;
begin
{$IFDEF USE_STATEMACHINE}
  Writeln('=== Testing with {$ASYNCMODE STATEMACHINE} ===');
{$ELSE}
  Writeln('=== Testing with {$ASYNCMODE FIBER} ===');
{$ENDIF}
  ProcDone := 0;
  BackgroundTask(777);
  Check('BackgroundTask returned immediately', ProcDone = 0);
  Sleep(40);
  Check('BackgroundTask completed asynchronously', ProcDone = 777);
  F1 := ComputeUser(21);
  Check('ComputeUser returns 42', F1.Value = 42);

  F2 := ComputePipeline(5);
  { (5 + 10) * 2 = 30 }
  Check('ComputePipeline returns 30', F2.Value = 30);

  F3 := DirectResult(7);
  Check('DirectResult returns 70', F3.Value = 70);
end;

begin
  Passed := 0;
  Failed := 0;
  RunTests;
  Writeln(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then
    Halt(1);
end.
