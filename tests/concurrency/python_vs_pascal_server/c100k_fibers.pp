program c100k_fibers;
{$mode objfpc}{$H+}
{$modeswitch anonymousfunctions}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, SyncObjs, System.Threading,
  eventloop.types, eventloop.core, fcleventloop, fclasync;

const
  COUNT = 100000;

var
  Loop: IEventLoop;
  Counter: Integer = 0;
  I: Integer;
  T0, Took: QWord;
begin
  Writeln('=== Modern Free Pascal: 100,000 Concurrent Fibers / Coroutines ===');
  Loop := TEventLoop.Create(bkAuto);
  T0 := GetTickCount64;

  for I := 1 to COUNT do
  begin
    SpawnAsync(
      procedure
      begin
        AsyncSleep(1);
        InterlockedIncrement(Counter);
      end, Loop);
  end;

  while Counter < COUNT do
    Loop.RunOnce(10);

  Took := GetTickCount64 - T0;

  Writeln('Executed ', COUNT, ' coroutines in: ', Took, ' ms');
  Writeln('Counter: ', Counter);
end.
