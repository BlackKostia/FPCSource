program test_sm_min;

{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$ASYNCMODE STATEMACHINE}

uses
  {$ifdef unix}cthreads,{$endif}
  System.Threading;

function P: specialize IFuture<Integer>; async;
begin
  Result := 1;
end;

begin
  if P.Value <> 1 then
    Halt(1);
  Writeln('ok');
end.
