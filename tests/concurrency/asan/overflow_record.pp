{ EXPECT: heap-buffer-overflow
  a 16-byte record read from the heap that crosses the end of the block
  (SSE or two 8-byte loads, depending on the code generator) }
program overflow_record;
{$mode objfpc}
type
  TVec = record
    X, Y: Double;
  end;
  PVec = ^TVec;
var
  P: PByte;
  V: TVec;
begin
  P := GetMem(24);
  FillChar(P^, 24, 0);
  V := PVec(P)^;
  WriteLn(V.X:0:1);
  V := PVec(P + 16)^; {ERR}
  WriteLn(V.Y:0:1);
  FreeMem(P);
end.
