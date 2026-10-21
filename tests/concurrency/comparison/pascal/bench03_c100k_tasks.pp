program bench03_c100k_tasks;

{ 20 000 await TTask.Delay(20) on the state-machine backend.
  Not part of the timed suite: bench03_c100k_fibers.pp still measures fibers. }

{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$ASYNCMODE STATEMACHINE}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, System.Threading;

const
  TotalCoroutines = 20000;

var
  CompletedCount: Integer = 0;
  TotalSum: Int64 = 0;

function WaitOne: ITask; async;
begin
  await TTask.Delay(20);
  InterlockedIncrement(CompletedCount);
  InterlockedExchangeAdd64(TotalSum, 1);
end;

var
  Tasks: array of ITask;
  I: Integer;
  T0, Took: QWord;
begin
  Writeln('=== Benchmark 3 (tasks): 20,000 await TTask.Delay(20) ===');
  SetLength(Tasks, TotalCoroutines);
  T0 := GetTickCount64;
  for I := 0 to TotalCoroutines - 1 do
    Tasks[I] := WaitOne;
  if not TTask.WaitForAll(Tasks) then
    Halt(2);
  Took := GetTickCount64 - T0;
  Writeln('All ', CompletedCount, ' tasks completed in: ', Took, ' ms');
  Writeln('Total accumulated sum: ', TotalSum);
  if (CompletedCount = TotalCoroutines) and (TotalSum = TotalCoroutines) then
    Writeln('BENCHMARK 3 PASSED')
  else
    Halt(1);
end.
