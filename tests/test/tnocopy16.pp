{ %FAIL }
{ generic code that copies its type parameter fails for a nocopy type }
program tnocopy16;

{$mode objfpc}

type
  TOwner = record
    Value: LongInt;
  end nocopy;

generic procedure Swap<T>(var a, b: T);
var
  tmp: T;
begin
  tmp := a;
  a := b;
  b := tmp;
end;

var
  a, b: TOwner;
begin
  specialize Swap<TOwner>(a, b);
end.
