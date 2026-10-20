{ TThread.WaitFor called from the main thread must return when the thread
  finishes, not when the 100 ms CheckSynchronize timeout of its wait loop
  expires }
{$mode objfpc}
program tthreadwaitforlatency;

uses
{$ifdef unix}
  cthreads,
{$endif}
  Classes, SysUtils;

type
  TShortThread = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TShortThread.Execute;
begin
  Sleep(5);
end;

const
  Rounds = 20;

var
  T: TShortThread;
  T0, Took, Slowest: QWord;
  I: Integer;
begin
  Slowest := 0;
  for I := 1 to Rounds do
    begin
      T0 := GetTickCount64;
      T := TShortThread.Create(False);
      T.WaitFor;
      Took := GetTickCount64 - T0;
      T.Free;
      if Took > Slowest then
        Slowest := Took;
    end;
  WriteLn('slowest WaitFor of a 5 ms thread: ', Slowest, ' ms');
  { the wait loop polled with a timeout of 100 ms }
  if Slowest >= 60 then
    Halt(1);
  WriteLn('ok');
end.
