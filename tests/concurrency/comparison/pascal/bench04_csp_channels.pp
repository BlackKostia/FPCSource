program bench04_csp_channels;
{$mode objfpc}{$H+}
{$modeswitch anonymousfunctions}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, SyncObjs, System.Threading;

const
  ItemCount = 100000;

var
  Chan: specialize TChannel<Integer>;
  ProducerTask, ConsumerTask: ITask;
  ConsumedSum: Int64 = 0;
  T0, Took: QWord;
begin
  Writeln('=== Benchmark 4: Go-style CSP Channel Communication ===');
  { Bounded channel with buffer 1024 }
  Chan := specialize TChannel<Integer>.Create(1024);
  T0 := GetTickCount64;

  { Producer task }
  ProducerTask := TTask.Run(
    procedure
    var
      I: Integer;
    begin
      for I := 1 to ItemCount do
        Chan.Send(I);
      Chan.Close;
    end);

  { Consumer task using for..in }
  ConsumerTask := TTask.Run(
    procedure
    var
      Msg: Integer;
    begin
      for Msg in Chan do
        ConsumedSum := ConsumedSum + Msg;
    end);

  TTask.WaitForAll([ProducerTask, ConsumerTask]);
  Took := GetTickCount64 - T0;

  Writeln('Transferred ', ItemCount, ' messages through channel in: ', Took, ' ms');
  Writeln('Calculated sum: ', ConsumedSum);

  Chan.Free;

  { Sum of 1..100000 = N*(N+1)/2 = 5000050000 }
  if (ConsumedSum = 5000050000) then
    Writeln('BENCHMARK 4 PASSED')
  else
    Halt(1);
end.

