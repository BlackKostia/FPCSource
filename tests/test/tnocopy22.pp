{ %FAIL }
{ a value parameter of a procedural type }
program tnocopy22;

{$mode objfpc}

type
  TOwner = record
    Value: LongInt;
  end nocopy;

  TProc = procedure(a: TOwner);

begin
end.
