{ %FAIL }
{ a forward declaration in a program repeats the constraints: different
  constraints in the implementation are an error }
program tgenconstraint55;

{$mode objfpc}{$H+}

generic function Id<T: class>(aObj: T): T; forward;

generic function Id<T: record>(aObj: T): T;
begin
  Result := aObj;
end;

begin
end.
