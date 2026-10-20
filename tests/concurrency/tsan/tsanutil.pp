{ Helpers for the ThreadSanitizer tests: run two thread functions so that
  they overlap in time. Both wait for one start event (a pthread condition
  variable, which ThreadSanitizer sees), so the helper itself is race-free. }
unit tsanutil;

{$mode objfpc}{$H+}

interface

type
  TWorker = procedure;

procedure RunPair(A, B: TWorker);

implementation

uses
  SysUtils, SyncObjs;

var
  Start: TEvent;

function Run(P: Pointer): PtrInt;
begin
  Start.WaitFor(INFINITE);
  TWorker(P)();
  Result := 0;
end;

procedure RunPair(A, B: TWorker);
var
  T1, T2: TThreadID;
begin
  Start := TEvent.Create(nil, True, False, '');
  T1 := BeginThread(@Run, Pointer(A));
  T2 := BeginThread(@Run, Pointer(B));
  Start.SetEvent;
  WaitForThreadTerminate(T1, 0);
  WaitForThreadTerminate(T2, 0);
  CloseThread(T1);
  CloseThread(T2);
  Start.Free;
end;

end.
