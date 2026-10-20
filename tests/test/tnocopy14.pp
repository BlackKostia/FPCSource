{ %FAIL }
{ Copy() of a dynamic array copies the elements }
program tnocopy14;

{$mode objfpc}

type
  TOwner = record
    Value: LongInt;
  end nocopy;

var
  a, b: array of TOwner;
begin
  SetLength(a, 1);
  b := Copy(a);
end.
