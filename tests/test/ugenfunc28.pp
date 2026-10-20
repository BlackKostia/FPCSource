unit ugenfunc28;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

type
  generic TBox<T> = record
    Obj: T;
  end;

  generic TClassBox<T: class> = record
    Obj: T;
  end;

{ the specializations in the headers of these generic routines are stored in
  the local symtable of the routines; it must stay valid after this unit has
  been compiled when the unit is compiled together with the program }
generic function MakeBox<T>(aValue: T): specialize TBox<T>;
generic function Unbox<T>(constref aBox: specialize TBox<T>): T;
generic function MakeClassBox<T: class>(aObj: T): specialize TClassBox<T>;
generic function UnboxClass<T: class>(constref aBox: specialize TClassBox<T>): T;

implementation

generic function MakeBox<T>(aValue: T): specialize TBox<T>;
begin
  Result.Obj := aValue;
end;

generic function Unbox<T>(constref aBox: specialize TBox<T>): T;
begin
  Result := aBox.Obj;
end;

generic function MakeClassBox<T>(aObj: T): specialize TClassBox<T>;
begin
  Result.Obj := aObj;
end;

generic function UnboxClass<T>(constref aBox: specialize TClassBox<T>): T;
begin
  Result := aBox.Obj;
end;

end.
