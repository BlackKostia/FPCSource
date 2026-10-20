{ %FAIL }
{ a generic routine with a value parameter specialized with a nocopy type }
program tnocopy23;

{$mode objfpc}

type
  TOwner = record
    Value: LongInt;
  end nocopy;

generic procedure Take<T>(a: T);
begin
end;

var
  a: TOwner;
begin
  specialize Take<TOwner>(a);
end.
