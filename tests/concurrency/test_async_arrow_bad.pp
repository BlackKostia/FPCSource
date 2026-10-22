program test_async_arrow_bad;

{ An async arrow whose target returns Integer is rejected: the prefix does
  not invent an IFuture<T> wrapper, and Integer is not a task type. }

{$mode objfpc}{$H+}
{$modeswitch arrowfunctions}
{$ASYNCMODE STATEMACHINE}

type
  TIntFn = reference to function: Integer;

var
  F: TIntFn;
begin
  F := async () => 1;
  if F() = 0 then
    ;
end.
