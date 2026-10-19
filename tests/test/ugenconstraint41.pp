unit ugenconstraint41;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

type
  generic TBox<T: class> = record
    Obj: T;
  end;

{ constrained generic routines declared in the interface whose result or
  parameter types specialize a generic that requires the same constraint;
  the implementation does not repeat the constraint }
generic function MakeBox<T: class>(aObj: T): specialize TBox<T>;
generic function Unbox<T: class>(constref aBox: specialize TBox<T>): T;
generic procedure FillBox<T: class>(out aBox: specialize TBox<T>; aObj: T);

implementation

generic function MakeBox<T>(aObj: T): specialize TBox<T>;
begin
  Result.Obj := aObj;
end;

generic function Unbox<T>(constref aBox: specialize TBox<T>): T;
begin
  Result := aBox.Obj;
end;

generic procedure FillBox<T>(out aBox: specialize TBox<T>; aObj: T);
begin
  aBox.Obj := aObj;
end;

end.
