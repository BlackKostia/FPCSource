{ EXPECT: race }
program race_dynarray;
{$mode objfpc}
uses {$ifdef unix}cthreads,{$endif} tsanutil;
var
  A: array of Word;
procedure Writer;
var
  I: Integer;
begin
  for I := 1 to 200000 do
    A[3] := I; {RACE}
end;
procedure Reader;
var
  I: Integer;
  S: LongInt;
begin
  S := 0;
  for I := 1 to 200000 do
    Inc(S, A[3]); {RACE}
  if S = -1 then
    WriteLn;
end;
begin
  SetLength(A, 8);
  RunPair(@Writer, @Reader);
  WriteLn('done ', Length(A));
end.
