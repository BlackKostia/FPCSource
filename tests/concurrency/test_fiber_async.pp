program test_fiber_async;

{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
{$modeswitch implicitgenerics}
{$ASYNCMODE FIBER}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, Classes, SyncObjs,
  System.Threading,
  eventloop.types, eventloop.core,
  fcleventloop,
  fclasync;

var
  Passed, Failed: Integer;
  ProcFlag: Integer = 0;

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

function DelayFuture(AMilliseconds: Integer; AValue: Integer): specialize IFuture<Integer>;
begin
  Result := TTask.Future(
    function: Integer
    begin
      Sleep(AMilliseconds);
      Result := AValue;
    end);
end;

{ 1. Standard unified async function: Result has type Integer, not IFuture<Integer> }
function FetchUser(id: Integer): specialize IFuture<Integer>; async;
begin
  Result := await DelayFuture(40, id * 2);
end;

{ 2. Multi-step await pipeline }
function PipelineFiber: specialize IFuture<Integer>; async;
var
  A, B: Integer;
begin
  A := await DelayFuture(30, 10);
  B := await DelayFuture(30, 20);
  Result := A + B + 12;
end;

{ 3. Async procedure (fire-and-forget via TFiber.Spawn) }
procedure BackgroundProc(val: Integer); async;
begin
  await DelayFuture(30, 0);
  ProcFlag := val;
end;

{ 4. Exception propagation }
function FaultedFiber: specialize IFuture<Integer>; async;
begin
  await DelayFuture(20, 0);
  raise Exception.Create('fiber boom');
  Result := 1;
end;

{ 5. Async function with early Exit }
function EarlyExitFiber(N: Integer): specialize IFuture<Integer>; async;
begin
  if N > 0 then
    begin
      Result := 42;
      Exit;
    end;
  Result := await DelayFuture(20, -1);
end;

{ 6. Recursive async function }
function RecursiveSum(N: Integer): specialize IFuture<Integer>; async;
var
  Prev: Integer;
begin
  if N <= 1 then
    Result := 1
  else
    begin
      Prev := await RecursiveSum(N - 1);
      Result := N + Prev;
    end;
end;

procedure TestUnifiedFiberAsync;
var
  F1, F2, F4, F5, F6: specialize IFuture<Integer>;
  T0, Took: QWord;
  Res: Integer;
  CaughtBoom: Boolean;
begin
  Writeln('--- 1. FetchUser (unified Result and await) ---');
  T0 := GetTickCount64;
  F1 := FetchUser(21);
  Took := GetTickCount64 - T0;
  Check('Call returns immediately (< 30ms)', Took < 30);
  Res := F1.Value;
  Check('FetchUser result is correct (42)', Res = 42);

  Writeln('--- 2. PipelineFiber (sequential awaits) ---');
  T0 := GetTickCount64;
  F2 := PipelineFiber;
  Took := GetTickCount64 - T0;
  Check('Pipeline returns immediately (< 30ms)', Took < 30);
  Res := F2.Value;
  Check('Pipeline result is correct (10 + 20 + 12 = 42)', Res = 42);

  Writeln('--- 3. BackgroundProc (async procedure) ---');
  ProcFlag := 0;
  BackgroundProc(99);
  Check('BackgroundProc returns immediately (flag still 0)', ProcFlag = 0);
  Sleep(70);
  Check('BackgroundProc finished asynchronously (flag is 99)', ProcFlag = 99);

  Writeln('--- 4. FaultedFiber (exception propagation) ---');
  F4 := FaultedFiber;
  CaughtBoom := False;
  try
    F4.Value;
  except
    on E: EAggregateException do
      begin
        CaughtBoom := True;
        Check('Caught expected exception message', (E.Count > 0) and (Pos('fiber boom', E.InnerExceptions[0].Message) > 0));
      end;
    on E: Exception do
      begin
        CaughtBoom := True;
        Check('Caught expected exception message', Pos('fiber boom', E.Message) > 0);
      end;
  end;
  Check('Exception was propagated to future', CaughtBoom);

  Writeln('--- 5. EarlyExitFiber ---');
  F5 := EarlyExitFiber(10);
  Check('Early exit result is 42', F5.Value = 42);

  Writeln('--- 6. RecursiveSum ---');
  F6 := RecursiveSum(5);
  { 5 + 4 + 3 + 2 + 1 = 15 }
  Check('Recursive sum of 5 is 15', F6.Value = 15);
end;

begin
  Passed := 0;
  Failed := 0;
  TestUnifiedFiberAsync;
  Writeln('====================================');
  Writeln(Format('%d passed, %d failed', [Passed, Failed]));
  if Failed > 0 then
    Halt(1);
end.
