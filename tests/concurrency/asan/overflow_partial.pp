{ EXPECT: heap-buffer-overflow
  ACCESS: READ of size 4
  a 4-byte read that ends inside the block passes, one that crosses its end
  by one byte is reported (partially addressable shadow granule) }
program overflow_partial;
{$mode objfpc}
var
  P: PByte;
  X, Y: LongInt;
begin
  P := GetMem(13);
  FillChar(P^, 13, 1);
  X := PLongInt(P + 9)^;
  WriteLn(X);
  Y := PLongInt(P + 10)^; {ERR}
  WriteLn(Y);
  FreeMem(P);
end.
