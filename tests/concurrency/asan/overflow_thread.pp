{ EXPECT: heap-buffer-overflow
  ACCESS: WRITE of size 2
  THREAD: T1
  an error in a thread started by BeginThread: ASan knows the thread
  (cthreads calls pthread_create through the interceptor of ASan) }
program overflow_thread;
{$mode objfpc}
uses {$ifdef unix}cthreads,{$endif} SysUtils;
var
  Buf: PWord;
function Work(P: Pointer): PtrInt;
var
  I: Integer;
begin
  for I := 0 to PtrInt(P) do
    Buf[I] := I; {ERR}
  Result := 0;
end;
var
  T: TThreadID;
begin
  Buf := GetMem(8 * SizeOf(Word));
  T := BeginThread(@Work, Pointer(PtrInt(8)));
  WaitForThreadTerminate(T, 0);
  CloseThread(T);
  WriteLn(Buf[0]);
end.
