{ %FAIL }
unit ugenconstraint53;

{$mode objfpc}{$H+}

interface

type
  generic TBox<T: class> = record
    Obj: T;
  end;

generic function MakeBox<T: class>(aObj: T): specialize TBox<T>;

implementation

generic function MakeBox<T>(aObj: T): specialize TBox<T>;
begin
  Result.Obj := aObj;
end;

{ an overload that exists only in the implementation does not inherit the
  constraint of the declaration above, so its result type is invalid }
generic function MakeBox<T>(aObj: T; aExtra: LongInt): specialize TBox<T>;
begin
  Result.Obj := aObj;
end;

end.
