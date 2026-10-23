program test_async_var_bad;
{$mode objfpc}{$H+}

{ Async routines must reject var parameters }
procedure Bad(var X: Integer); async;
begin
end;

begin
end.
