program test_statemachine_await_expr;

{ await inside a larger expression is rejected, not rewritten to a blocking Wait. }

{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$ASYNCMODE STATEMACHINE}

uses
  {$ifdef unix}cthreads,{$endif}
  System.Threading;

function Bad: specialize IFuture<Integer>; async;
var
  A, B: specialize IFuture<Integer>;
begin
  Result := await A + await B;
end;

begin
  if Bad.Value <> 0 then
    Halt(1);
end.
