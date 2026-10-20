{ EXPECT: norace
  writes to different bytes/halves of one 8-byte word do not conflict:
  checks that accesses are reported with their real size }
program norace_disjoint_sizes;
{$mode objfpc}
uses {$ifdef unix}cthreads,{$endif} tsanutil;
type
  TRec = packed record
    case Integer of
      0: (B0, B1, B2, B3: Byte; L1: LongInt);
      1: (W0, W1: Word; L2: LongInt);
      2: (Q: Int64);
  end;
var
  R: TRec;
procedure LowBytes;
var
  I: Integer;
begin
  for I := 1 to 100000 do
  begin
    R.B0 := Byte(I);
    R.B1 := Byte(I + 1);
  end;
end;
procedure HighParts;
var
  I: Integer;
begin
  for I := 1 to 100000 do
  begin
    R.W1 := Word(I);
    R.L1 := I;
  end;
end;
begin
  RunPair(@LowBytes, @HighParts);
  WriteLn('done');
end.
