unit ugenconstraint52;

{$mode delphi}{$H+}

interface

type
  TBox<T: class> = record
    Obj: T;
  end;

  TCtorBox<T: class, constructor> = record
    Obj: T;
  end;

  TBoxes = record
    class function Make<T: class>(aObj: T): TBox<T>; static;
  end;

{ Delphi syntax; the class+constructor constraint is Delphi mode only }
function MakeBox<T: class>(aObj: T): TBox<T>;
function NewBox<T: class, constructor>: TCtorBox<T>;

implementation

function MakeBox<T>(aObj: T): TBox<T>;
begin
  Result.Obj := aObj;
end;

function NewBox<T>: TCtorBox<T>;
begin
  Result.Obj := T.Create;
end;

class function TBoxes.Make<T>(aObj: T): TBox<T>;
begin
  Result.Obj := aObj;
end;

end.
