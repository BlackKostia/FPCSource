unit ugenconstraint44;

{$mode objfpc}{$H+}

interface

type
  TBase = class
    function Name: String; virtual;
  end;

  IGreeter = interface
    ['{6A0B1F57-6E5B-4C59-9A62-0A2D8C2F7E11}']
    function Greet: String;
  end;

  generic TClassHolder<T: TBase> = record
    Item: T;
  end;

  generic TIntfHolder<T: IGreeter> = record
    Item: T;
  end;

{ different kinds of constraints: concrete class and interface }
generic function HoldBase<T: TBase>(aItem: T): specialize TClassHolder<T>;
generic function HoldIntf<T: IGreeter>(aItem: T): specialize TIntfHolder<T>;

implementation

function TBase.Name: String;
begin
  Result := 'base';
end;

generic function HoldBase<T>(aItem: T): specialize TClassHolder<T>;
begin
  Result.Item := aItem;
  { the constraint is visible in the body as well }
  if aItem.Name = '' then
    Result.Item := nil;
end;

generic function HoldIntf<T>(aItem: T): specialize TIntfHolder<T>;
begin
  Result.Item := aItem;
end;

end.
