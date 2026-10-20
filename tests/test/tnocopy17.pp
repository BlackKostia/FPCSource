{ %FAIL }
{ the nocopy flag of a type from another unit (ppu) }
program tnocopy17;

{$mode objfpc}

uses
  unocopy2;

var
  a, b: TPlain;
begin
  b := a;
end.
