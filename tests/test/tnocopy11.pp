{ %FAIL }
{ value parameter of a nocopy type }
program tnocopy11;

{$mode objfpc}

type
  TOwner = record
    Value: LongInt;
  end nocopy;

procedure Take(a: TOwner);
begin
end;

begin
end.
