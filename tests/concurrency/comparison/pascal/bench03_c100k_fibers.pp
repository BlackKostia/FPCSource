program bench03_c100k_fibers;
{$mode objfpc}{$H+}
{$modeswitch anonymousfunctions}
{$modeswitch arrowfunctions}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, SyncObjs, System.Threading,
  eventloop.types, eventloop.core, fcleventloop, fclasync;

const
  TotalCoroutines = 20000;

var
  Loop: IEventLoop;
  CompletedCount: Integer = 0;
  TotalSum: Int64 = 0;
  T0, Took: QWord;
  I: Integer;
begin
  Writeln('=== Benchmark 3: 20,000 Concurrent Coroutines / Fibers ===');
  Loop := TEventLoop.Create(bkAuto);
  T0 := GetTickCount64;

  for I := 1 to TotalCoroutines do
  begin
    SpawnAsync(
      procedure
      begin
        { Non-blocking sleep on event loop timer }
        AsyncSleep(20, Loop);
        InterlockedIncrement(CompletedCount);
        InterlockedExchangeAdd64(TotalSum, 1);
      end, Loop, 32 * 1024);
  end;

  { Run event loop until all 20,000 fibers finish }
  while (CompletedCount < TotalCoroutines) and (GetTickCount64 - T0 < 10000) do
    Loop.RunOnce(10);

  Took := GetTickCount64 - T0;

  Writeln('All ', CompletedCount, ' fibers completed on 1 OS thread in: ', Took, ' ms');
  Writeln('Total accumulated sum: ', TotalSum);

  if (CompletedCount = TotalCoroutines) and (TotalSum = TotalCoroutines) then
    Writeln('BENCHMARK 3 PASSED')
  else
    Halt(1);
end.

