{ %FAIL }
{ a record containing a nocopy field is not copyable either }
program tnocopy12;

{$mode objfpc}

type
  TOwner = record
    Value: LongInt;
  end nocopy;

  TPair = record
    Name: String;
    Item: TOwner;
  end;

var
  a, b: TPair;
begin
  b := a;
end.
