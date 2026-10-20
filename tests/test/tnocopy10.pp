{ %FAIL }
{ assignment of a variable of a nocopy type }
program tnocopy10;

{$mode objfpc}

type
  TOwner = record
    Value: LongInt;
  end nocopy;

var
  a, b: TOwner;
begin
  b := a;
end.
