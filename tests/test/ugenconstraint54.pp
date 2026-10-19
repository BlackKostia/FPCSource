unit ugenconstraint54;

{$mode objfpc}{$H+}

interface

type
  generic TBox<T: class> = record
    Obj: T;
  end;

generic function MakeBox<T: class>(aObj: T): specialize TBox<T>;
function PickViaOverload(aObj: TObject; aCount: LongInt): TObject;

implementation

generic function MakeBox<T>(aObj: T): specialize TBox<T>;
begin
  Result.Obj := aObj;
end;

{ an overload that exists only in the implementation and has the same type
  parameter name: its header is checked as usual (the deferred checks of
  the declaration's constraints do not apply to it) }
generic function MakeBox<T>(aObj: T; aCount: LongInt): T;
begin
  if aCount > 0 then
    Result := aObj
  else
    Result := Default(T);
end;

function PickViaOverload(aObj: TObject; aCount: LongInt): TObject;
begin
  Result := specialize MakeBox<TObject>(aObj, aCount);
end;

end.
