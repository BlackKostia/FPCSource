{ EXPECT: race }
program race_global;
{$mode objfpc}
uses {$ifdef unix}cthreads,{$endif} tsanutil;
var
  Counter: LongInt;
procedure Work;
var
  I: Integer;
begin
  for I := 1 to 200000 do
    Inc(Counter); {RACE}
end;
begin
  RunPair(@Work, @Work);
  WriteLn('done ', Counter > 0);
end.
