{ %FAIL }
{ a static array of a nocopy type is not copyable }
program tnocopy13;

{$mode objfpc}

type
  TOwner = record
    Value: LongInt;
  end nocopy;

var
  a, b: array[0..1] of TOwner;
begin
  b := a;
end.
