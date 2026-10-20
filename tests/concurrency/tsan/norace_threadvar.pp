{ EXPECT: norace
  every thread has its own threadvar and stack }
program norace_threadvar;
{$mode objfpc}
uses {$ifdef unix}cthreads,{$endif} tsanutil;
threadvar
  PerThread: LongInt;
var
  Results: array[0..1] of Int64;
  Slot: LongInt;
procedure Work;
var
  Local: array[0..255] of LongInt;
  I, Me: Integer;
  S: Int64;
begin
  Me := InterlockedIncrement(Slot) - 1;
  for I := 0 to 255 do
    Local[I] := I * 3;
  S := 0;
  for I := 1 to 100000 do
  begin
    Inc(PerThread);
    Inc(S, Local[I and 255]);
  end;
  Results[Me] := S + PerThread;
end;
begin
  RunPair(@Work, @Work);
  WriteLn('r0=', Results[0], ' r1=', Results[1]);
end.
