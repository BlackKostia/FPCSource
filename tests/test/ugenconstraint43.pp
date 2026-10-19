unit ugenconstraint43;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

type
  generic TBox<T: class> = record
    Obj: T;
  end;

  { generic methods with constrained type parameters in records and classes }
  TBoxes = record
    generic class function Make<T: class>(aObj: T): specialize TBox<T>; static;
    generic function Get<T: class>(constref aBox: specialize TBox<T>): T;
  end;

  TBoxFactory = class
    generic function Make<T: class>(aObj: T): specialize TBox<T>;
    generic class function MakeStatic<T: class>(aObj: T): specialize TBox<T>; static;
  end;

implementation

generic class function TBoxes.Make<T>(aObj: T): specialize TBox<T>;
begin
  Result.Obj := aObj;
end;

generic function TBoxes.Get<T>(constref aBox: specialize TBox<T>): T;
begin
  Result := aBox.Obj;
end;

generic function TBoxFactory.Make<T>(aObj: T): specialize TBox<T>;
begin
  Result.Obj := aObj;
end;

generic class function TBoxFactory.MakeStatic<T>(aObj: T): specialize TBox<T>;
begin
  Result.Obj := aObj;
end;

end.
