{ EXPECT: clean
  single-threaded code with many kinds of memory accesses: no reports, and
  the output is the same with and without -fsanitize=address }
program clean_correctness;
{$mode objfpc}{$H+}
uses {$ifdef unix}cthreads,{$endif} SysUtils;
type
  TPoint3 = record
    X, Y, Z: Double;
  end;
  TBig = record
    A: array[0..31] of LongInt;
    S: ShortString;
  end;
  TSetOfByte = set of Byte;
var
  Ints: array of LongInt;
  Bytes: array[0..63] of Byte;
  Pts: array[0..15] of TPoint3;
  Big1, Big2: TBig;
  Ext: Extended;
  Sng: Single;
  Str, Str2: AnsiString;
  WStr: UnicodeString;
  Bits: TSetOfByte;
  Q: QWord;
  I, J: Integer;
  Sum: Int64;
  D: Double;
  P: PLongInt;
  Cur: Currency;
  Cmp: Boolean;
begin
  SetLength(Ints, 1000);
  for I := 0 to High(Ints) do
    Ints[I] := (I * 7919) xor (I shl 3);
  Sum := 0;
  for I := 0 to High(Ints) do
    if Ints[I] > Ints[(I + 1) mod Length(Ints)] then
      Inc(Sum, Ints[I] - I)
    else
      Dec(Sum, I);
  WriteLn('ints ', Sum);

  for I := 0 to 63 do
    Bytes[I] := Byte(I * 37);
  Q := 0;
  for I := 0 to 63 do
    Q := (Q shl 1) xor Bytes[I] xor (Q shr 63);
  WriteLn('bytes ', Q);

  for I := 0 to 15 do
  begin
    Pts[I].X := I * 0.5;
    Pts[I].Y := Sqrt(I + 1.0);
    Pts[I].Z := Pts[I].X * Pts[I].Y - 1.25;
  end;
  D := 0;
  for I := 0 to 15 do
    D := D + Pts[I].X * Pts[I].Z / (Pts[I].Y + 1);
  WriteLn('sse ', D:0:9);

  Ext := 1;
  for I := 1 to 20 do
    Ext := Ext * I / 3 + Ln(I);
  Sng := Ext / 1e15;
  WriteLn('x87 ', Ext:0:6, ' ', Sng:0:4);

  Cur := 12.3456;
  for I := 1 to 10 do
    Cur := Cur * 1.5 - 2;
  WriteLn('currency ', CurrToStr(Cur));

  for I := 0 to 31 do
    Big1.A[I] := I * I;
  Big1.S := 'record copy';
  Big2 := Big1;
  Big2.A[5] := -1;
  WriteLn('records ', Big1.A[5], ' ', Big2.A[5], ' ', Big2.A[31], ' ', Big2.S);

  Str := '';
  for I := 1 to 50 do
    Str := Str + IntToStr(I mod 7);
  Str2 := Copy(Str, 10, 20);
  WStr := UnicodeString(Str2) + ' ' + UnicodeString(IntToHex(Length(Str), 4));
  WriteLn('strings ', Length(Str), ' ', Str2, ' ', AnsiString(WStr), ' ', Pos('65', Str));

  Bits := [];
  for I := 0 to 255 do
    if I mod 3 = 0 then
      Include(Bits, I);
  J := 0;
  for I := 0 to 255 do
    if I in Bits then
      Inc(J);
  WriteLn('sets ', J);

  New(P);
  P^ := 10;
  for I := 1 to 10 do
    P^ := P^ * 2 - I;
  WriteLn('pointer ', P^);
  Dispose(P);

  Cmp := (Ints[10] < Ints[20]) and (Bytes[1] <> Bytes[2]);
  WriteLn('flags ', Cmp);
  try
    raise Exception.Create('caught');
  except
    on E: Exception do
      WriteLn('exception ', E.Message);
  end;
end.
