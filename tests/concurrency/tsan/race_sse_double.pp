{ EXPECT: race }
program race_sse_double;
{$mode objfpc}
uses {$ifdef unix}cthreads,{$endif} tsanutil;
var
  X: Double;
procedure Work;
var
  I: Integer;
begin
  for I := 1 to 200000 do
    X := X * 1.0000001 + 0.5; {RACE}
end;
begin
  X := 1;
  RunPair(@Work, @Work);
  WriteLn('done ', X > 0);
end.
