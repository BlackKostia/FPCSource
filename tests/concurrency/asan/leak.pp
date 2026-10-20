{ EXPECT: detected memory leaks
  LeakSanitizer (part of ASan) checks the heap at exit. The routines of the
  RTL have no frame pointer, so the allocation stack starts at the caller
  of the routine that calls GetMem (Lose here) }
program leak;
{$mode objfpc}
procedure Lose;
var
  P: Pointer;
begin
  P := GetMem(100);
  FillChar(P^, 100, 0);
  P := nil;
end;
begin
  Lose; {ERR}
  WriteLn('done');
end.
