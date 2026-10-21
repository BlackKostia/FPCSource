program test_statemachine_await_bad;

{ await in a condition is rejected: it must not become a blocking Wait. }

{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$ASYNCMODE STATEMACHINE}

uses
  {$ifdef unix}cthreads,{$endif}
  System.Threading;

function Bad: ITask; async;
begin
  if await TTask.Delay(1) then
    ;
end;

begin
  Bad;
end.
