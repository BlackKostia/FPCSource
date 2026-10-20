{ EXPECT: attempting double-free
  the second FreeMem goes through cmem to free(), which ASan checks. The
  routines of the RTL have no frame pointer, so the stack of free() starts
  at the caller of the routine that calls FreeMem (Release here) }
program double_free;
{$mode objfpc}
procedure Release(P: Pointer);
begin
  FreeMem(P);
end;
var
  P: Pointer;
begin
  P := GetMem(32);
  Release(P);
  Release(P); {ERR}
  WriteLn('not reached');
end.
