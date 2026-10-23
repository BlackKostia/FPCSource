{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
{$modeswitch implicitgenerics}
{$IFDEF USE_FIBER}
{$ASYNCMODE FIBER}
{$ELSE}
{$ASYNCMODE STATEMACHINE}
{$ENDIF}

program test_if_await;

uses
  {$ifdef unix}cthreads,{$endif}
  sysutils, system.threading, fclasync;

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

function DelayBool(AMs: Integer; Val: Boolean): specialize IFuture<Boolean>;
begin
  Result := TTask.Future(
    function: Boolean
    begin
      Sleep(AMs);
      Result := Val;
    end);
end;

function DelayInt(AMs: Integer; Val: Integer): specialize IFuture<Integer>;
begin
  Result := TTask.Future(
    function: Integer
    begin
      Sleep(AMs);
      Result := Val;
    end);
end;

{ 1. Direct if await }
function TestIfAwaitDirect(CondVal: Boolean): specialize IFuture<Integer>; async;
begin
  if await DelayBool(20, CondVal) then
    Result := 100
  else
    Result := 200;
end;

{ 2. if not await }
function TestIfNotAwait(CondVal: Boolean): specialize IFuture<Integer>; async;
begin
  if not await DelayBool(20, CondVal) then
    Result := 100
  else
    Result := 200;
end;

{ 3. if comparison with await }
function TestIfCompareAwait(X: Integer): specialize IFuture<Integer>; async;
begin
  if (await DelayInt(20, X)) = 42 then
    Result := 1
  else
    Result := 0;
end;

begin
  Passed := 0;
  Failed := 0;

  Writeln('=== Testing if await in STATEMACHINE mode ===');
  Check('TestIfAwaitDirect(True) = 100', TestIfAwaitDirect(True).Value = 100);
  Check('TestIfAwaitDirect(False) = 200', TestIfAwaitDirect(False).Value = 200);

  Check('TestIfNotAwait(True) = 200', TestIfNotAwait(True).Value = 200);
  Check('TestIfNotAwait(False) = 100', TestIfNotAwait(False).Value = 100);

  Check('TestIfCompareAwait(42) = 1', TestIfCompareAwait(42).Value = 1);
  Check('TestIfCompareAwait(99) = 0', TestIfCompareAwait(99).Value = 0);

  Writeln(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then
    Halt(1);
end.
