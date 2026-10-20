{ %FAIL }
{ copying from a field, an array element or a dereferenced pointer }
program tnocopy18;

{$mode objfpc}

type
  TOwner = record
    Value: LongInt;
  end nocopy;

  THolder = class
    Item: TOwner;
  end;

var
  h: THolder;
  a: TOwner;
begin
  h := THolder.Create;
  a := h.Item;
end.
