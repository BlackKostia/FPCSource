{ %FAIL }
unit ugenconstraint51;

{$mode objfpc}{$H+}

interface

type
  generic TBox<T: class> = record
    Obj: T;
  end;

  generic TRecBox<T: record> = record
    Item: T;
  end;

generic function MakeBox<T: class>(aObj: T): specialize TBox<T>;

implementation

{ the inherited constraint (class) does not satisfy a record constraint }
generic function MakeBox<T>(aObj: T): specialize TBox<T>;
var
  r: specialize TRecBox<T>;
begin
  Result.Obj := aObj;
end;

end.
