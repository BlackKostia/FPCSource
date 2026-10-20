{ %FAIL }
{ copying from an array element }
program tnocopy19;

{$mode objfpc}

type
  TOwner = record
    Value: LongInt;
  end nocopy;

var
  arr: array of TOwner;
  a: TOwner;
begin
  SetLength(arr, 1);
  a := arr[0];
end.
