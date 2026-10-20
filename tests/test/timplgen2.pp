{ %FAIL }
{ implicitgenerics infers T = integer from DoCallback; a procedure with a
  parameter of another type does not match TProc<T, 10> for any T with a
  default value 10 of type T }
{$mode objfpc}
{$modeswitch implicitgenerics}
program timplgen2;

type
  generic TProc<T; const U: integer> = procedure(value: T = U);

generic procedure Run<T>(proc: specialize TProc<T, 10>);
begin
  proc();
end;

procedure DoStr(value: string);
begin
end;

begin
  Run(@DoStr);
end.
