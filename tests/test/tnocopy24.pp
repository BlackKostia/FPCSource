{ %FAIL }
{ "nocopy" given twice }
program tnocopy24;

{$mode objfpc}

type
  TOwner = record
    Value: LongInt;
  end nocopy nocopy;

begin
end.
