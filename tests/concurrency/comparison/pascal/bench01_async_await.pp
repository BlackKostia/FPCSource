program bench01_async_await;
{$mode objfpc}{$H+}
{$modeswitch anonymousfunctions}
{$modeswitch arrowfunctions}
{$modeswitch implicitgenerics}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, System.Threading, fclasync;

function DelayAsync(AMs, AVal: Integer): specialize IFuture<Integer>;
begin
  Result := TTask.Future(
    function: Integer
    begin
      Sleep(AMs);
      Result := AVal;
    end);
end;

function ComputeAsync(X: Integer): specialize IFuture<Integer>; async;
begin
  Result := specialize RunAsync<Integer>(
    function: Integer
    var
      A, B: Integer;
    begin
      A := await DelayAsync(40, X);
      B := await DelayAsync(40, A * 2);
      Result := B + 10;
    end);
end;

var
  T0, T1, TookCall, TookTotal: QWord;
  F: specialize IFuture<Integer>;
  Res: Integer;
begin
  Writeln('=== Benchmark 1: Async / Await Future ===');
  T0 := GetTickCount64;
  F := ComputeAsync(25);
  T1 := GetTickCount64;
  TookCall := T1 - T0;

  Writeln('Call to async function took: ', TookCall, ' ms (Non-blocking: ', TookCall < 20, ')');

  Res := await F;
  TookTotal := GetTickCount64 - T0;

  Writeln('Computed result: ', Res, ' (Expected: 60)');
  Writeln('Total execution time: ', TookTotal, ' ms');
  if (Res = 60) and (TookCall < 20) and (TookTotal >= 80) then
    Writeln('BENCHMARK 1 PASSED')
  else
    Halt(1);
end.

