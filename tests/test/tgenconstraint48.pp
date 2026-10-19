{ %FAIL }
{ an unconstrained type parameter of a routine without a constrained forward
  declaration must still be rejected by a constrained generic }
program tgenconstraint48;

{$mode objfpc}{$H+}

type
  generic TBox<T: class> = record
    Obj: T;
  end;

generic function MakeBox<T>(aObj: T): specialize TBox<T>;
begin
  Result.Obj := aObj;
end;

begin
end.
