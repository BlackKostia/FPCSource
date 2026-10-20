program spans_parallel;
// Зрізи пам'яті модуля spans: TSpan<T> / TReadOnlySpan<T> — вікна в масив
// чи рядок без копіювання; Chunk ділить роботу між паралельними задачами.
{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, System.Threading, spans;

type
  TDoubleSpan = specialize TSpan<Double>;

const
  N = 1000000;

// Приймає будь-який неперервний шматок: весь масив, його частину, Chunk.
function SumOf(const aValues: TDoubleSpan.TReadOnly): Double;
var
  X: Double;
begin
  Result := 0;
  for X in aValues do              // for..in — без перевірок меж
    Result := Result + X;
end;

var
  Data: array of Double;
  Whole: TDoubleSpan;
  Partial: array of Double;
  Parts, I: Integer;
  Total: Double;
  Line: AnsiString;
  Text: TReadOnlyAnsiCharSpan;
  EqPos: SizeInt;
  Key, Value: AnsiString;
begin
  WriteLn('1. A view without copying');
  SetLength(Data, N);
  for I := 0 to N - 1 do
    Data[I] := I mod 10;
  Whole := TDoubleSpan.Create(Data);
  WriteLn('  same memory: ', Whole.Data = @Data[0], ', length: ', Whole.Length);
  WriteLn('  sum of the first 20: ', SumOf(Whole.Slice(0, 20)):0:0);

  WriteLn('2. Bounds are always checked');
  try
    Whole[Whole.Length] := 1;
  except
    on E: ERangeError do
      WriteLn('  ', E.ClassName, ': ', E.Message);
  end;

  WriteLn('3. Non-overlapping chunks for parallel tasks');
  Parts := 8;
  SetLength(Partial, Parts);
  TParallel.&For(0, Parts - 1,
    procedure(aIndex: Integer)
    var
      Chunk: TDoubleSpan;
      J: SizeInt;
    begin
      // кожна задача пише лише у свій шматок — блокування не потрібні
      Chunk := Whole.Chunk(aIndex, Parts);
      for J := 0 to Chunk.Length - 1 do
        Chunk[J] := Chunk[J] * 2;
      Partial[aIndex] := SumOf(Chunk);
    end);
  Total := 0;
  for I := 0 to Parts - 1 do
    Total := Total + Partial[I];
  WriteLn('  total: ', Total:0:0, ' (expected ', SumOf(Whole):0:0, ')');
  WriteLn('  chunk 0 and 1 overlap: ', Whole.Chunk(0, Parts).Overlaps(Whole.Chunk(1, Parts)));

  WriteLn('4. Strings: slicing without Copy');
  Line := 'timeout=30';
  Text := SpanOf(Line);
  EqPos := -1;
  for I := 0 to Text.Length - 1 do
    if Text[I] = '=' then
    begin
      EqPos := I;
      Break;
    end;
  SetString(Key, Text.Slice(0, EqPos).Data, EqPos);
  SetString(Value, Text.Slice(EqPos + 1).Data, Text.Length - EqPos - 1);
  WriteLn('  key: ', Key, ', value: ', Value);
end.
