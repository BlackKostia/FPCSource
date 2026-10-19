{ %FAIL }
unit ugenconstraint49;

{$mode objfpc}{$H+}

interface

type
  generic TBox<T: class> = record
    Obj: T;
  end;

generic function MakeBox<T: class>(aObj: T): specialize TBox<T>;

implementation

{ constraints must not be repeated in the implementation of a routine that
  is declared in the interface }
generic function MakeBox<T: class>(aObj: T): specialize TBox<T>;
begin
  Result.Obj := aObj;
end;

end.
