{ EXPECT: norace }
program norace_mutex;
{$mode objfpc}
uses {$ifdef unix}cthreads,{$endif} SyncObjs, tsanutil;
var
  Counter: LongInt;
  Lock: TCriticalSection;
procedure Work;
var
  I: Integer;
begin
  for I := 1 to 100000 do
  begin
    Lock.Enter;
    Inc(Counter);
    Lock.Leave;
  end;
end;
begin
  Lock := TCriticalSection.Create;
  RunPair(@Work, @Work);
  WriteLn('counter=', Counter);
  Lock.Free;
end.
