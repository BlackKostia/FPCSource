{ EXPECT: clean
  scalar SSE accesses (movsd/movss) to the last field of a heap block are
  8 and 4 bytes wide, not the width of the xmm register }
program clean_scalar_sse;
{$mode objfpc}
type
  TRec = record
    A: LongInt;
    S: Single;
    D: Double;
  end;
  PRec = ^TRec;
var
  P: PRec;
  I: Integer;
begin
  P := GetMem(SizeOf(TRec));
  P^.A := 1;
  P^.S := 0;
  P^.D := 0;
  for I := 1 to 10 do
  begin
    P^.D := P^.D + I / 4;
    P^.S := P^.S + I;
  end;
  WriteLn(P^.D:0:2, ' ', P^.S:0:1);
  FreeMem(P);
end.
