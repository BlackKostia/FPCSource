{ EXPECT: norace
  an event (pthread condition variable) orders the producer and consumer }
program norace_event;
{$mode objfpc}
uses {$ifdef unix}cthreads,{$endif} SysUtils, SyncObjs;
var
  Message: AnsiString;
  Number: Int64;
  Ready: TEvent;
function Producer(P: Pointer): PtrInt;
begin
  Message := 'hello from producer';
  Number := 42;
  Ready.SetEvent;
  Result := 0;
end;
var
  T: TThreadID;
begin
  Ready := TEvent.Create(nil, True, False, '');
  T := BeginThread(@Producer, nil);
  Ready.WaitFor(INFINITE);
  WriteLn(Message, ' ', Number);
  WaitForThreadTerminate(T, 0);
  CloseThread(T);
  Ready.Free;
end.
