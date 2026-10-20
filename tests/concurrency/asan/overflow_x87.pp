{ EXPECT: heap-buffer-overflow
  ACCESS: READ of size 10
  an Extended (10 bytes, x87 fldt) read from an 8-byte block }
program overflow_x87;
{$mode objfpc}
var
  P: Pointer;
  E: Extended;
begin
  P := GetMem(8);
  FillChar(P^, 8, 0);
  E := PExtended(P)^; {ERR}
  WriteLn(E:0:1);
end.
