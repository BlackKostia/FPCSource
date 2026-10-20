{ EXPECT: race
  a 2-byte write at offset 0 and a 1-byte write at offset 1 overlap }
program race_overlapping_sizes;
{$mode objfpc}
uses {$ifdef unix}cthreads,{$endif} tsanutil;
type
  TRec = packed record
    case Integer of
      0: (W: Word; Pad: array[0..5] of Byte);
      1: (B0, B1: Byte);
  end;
var
  R: TRec;
procedure WriteWord;
var
  I: Integer;
begin
  for I := 1 to 200000 do
    R.W := I; {RACE}
end;
procedure WriteByte;
var
  I: Integer;
begin
  for I := 1 to 200000 do
    R.B1 := Byte(I); {RACE}
end;
begin
  RunPair(@WriteWord, @WriteByte);
  WriteLn('done');
end.
