program test_async_out_bad;
{$mode objfpc}{$H+}

{ Async routines must reject out parameters }
procedure Bad(out S: String); async;
begin
end;

begin
end.
