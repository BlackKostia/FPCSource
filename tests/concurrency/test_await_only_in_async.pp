program test_await_only_in_async;

{ await outside the current async routine is rejected (03381).
  A plain procedure, the main program and an arrow without the async
  prefix must not compile. The await in Outer itself is legal.
  This file is expected to fail compilation. }

{$mode objfpc}{$H+}
{$modeswitch arrowfunctions}
{$modeswitch functionreferences}
{$ASYNCMODE STATEMACHINE}

uses
  {$ifdef unix}cthreads,{$endif}
  System.Threading;

procedure Plain;
begin
  await TTask.Delay(1);
end;

function Outer: specialize IFuture<Integer>; async;
begin
  await TTask.Delay(1);
  Result := 1;
end;

var
  Step: reference to function: Integer;

begin
  Step := () =>
    begin
      await TTask.Delay(1);
      Result := 1;
    end;
  await TTask.Delay(1);
  Plain;
  if Outer.Value <> 1 then
    Halt(1);
end.
