{ EXPECT: norace
  two threads write adjacent Double fields with scalar SSE stores (8 bytes
  each, not the 16 bytes of the xmm register) }
program norace_adjacent_double;
{$mode objfpc}
uses {$ifdef unix}cthreads,{$endif} tsanutil;
type
  TRec = record
    D1, D2: Double;
  end;
var
  R: TRec;
procedure WriteFirst;
var
  I: Integer;
begin
  for I := 1 to 100000 do
    R.D1 := R.D1 + 0.5;
end;
procedure WriteSecond;
var
  I: Integer;
begin
  for I := 1 to 100000 do
    R.D2 := R.D2 + 0.25;
end;
begin
  RunPair(@WriteFirst, @WriteSecond);
  WriteLn('done ', R.D1 + R.D2 > 0);
end.
