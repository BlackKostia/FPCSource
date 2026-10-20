{ %FAIL }
{ copying from a dereferenced pointer }
program tnocopy20;

{$mode objfpc}

type
  TOwner = record
    Value: LongInt;
  end nocopy;
  POwner = ^TOwner;

var
  p: POwner;
  a: TOwner;
begin
  New(p);
  a := p^;
end.
