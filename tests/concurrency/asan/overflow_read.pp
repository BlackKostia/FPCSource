{ EXPECT: heap-buffer-overflow
  ACCESS: READ of size 1 }
program overflow_read;
{$mode objfpc}
var
  P: PByte;
  I, Sum: Integer;
begin
  P := GetMem(10);
  for I := 0 to 9 do
    P[I] := I;
  Sum := 0;
  for I := 0 to 10 do
    Sum := Sum + P[I]; {ERR}
  WriteLn(Sum);
  FreeMem(P);
end.
