{ EXPECT: race }
program race_heap_field;
{$mode objfpc}
uses {$ifdef unix}cthreads,{$endif} tsanutil;
type
  TData = class
    Value: Int64;
  end;
var
  D: TData;
procedure Work;
var
  I: Integer;
begin
  for I := 1 to 200000 do
    D.Value := D.Value + 1; {RACE}
end;
begin
  D := TData.Create;
  RunPair(@Work, @Work);
  WriteLn('done ', D.Value > 0);
  D.Free;
end.
