program bench07_cancellation;
{$mode objfpc}{$H+}
{$modeswitch anonymousfunctions}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, SyncObjs, System.Threading;

var
  Cts: TCancellationTokenSource;
  Token: TCancellationToken;
  Task1: ITask;
  LoopsDone: Integer = 0;
  T0, Took: QWord;
begin
  Writeln('=== Benchmark 7: Cooperative Cancellation Tokens ===');
  Cts := TCancellationTokenSource.Create;
  Token := Cts.Token;

  T0 := GetTickCount64;

  Task1 := TTask.Run(
    procedure
    begin
      while not Token.IsCancellationRequested do
      begin
        Sleep(5);
        Inc(LoopsDone);
      end;
    end);

  { Let task run for ~50ms then cancel }
  Sleep(50);
  Cts.Cancel;

  Task1.Wait;
  Took := GetTickCount64 - T0;

  Writeln('Task terminated gracefully after ', LoopsDone, ' iterations in: ', Took, ' ms');
  Cts.Free;

  if (LoopsDone >= 5) and (Took < 150) then
    Writeln('BENCHMARK 7 PASSED')
  else
    Halt(1);
end.

