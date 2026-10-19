{ %FAIL }
unit ugenconstraint50;

{$mode objfpc}{$H+}

interface

type
  generic TBox<T: class> = record
    Obj: T;
  end;

generic function MakeBox<T: class>(aObj: T): specialize TBox<T>;

implementation

{ the type parameter names must match the declaration }
generic function MakeBox<U>(aObj: U): specialize TBox<U>;
begin
  Result.Obj := aObj;
end;

end.
