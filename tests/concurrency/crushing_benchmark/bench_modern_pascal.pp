program bench_modern_pascal;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
{$modeswitch implicitgenerics}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, SyncObjs, System.Threading;

const
  TOTAL_OPS = 2000000;
  KEYS_COUNT = 1000;
  NUM_WORKERS = 12;

type
  TTradeEvent = record
    KeyId: Integer;
    Price: Int64;
    Checksum: QWord;
  end;

var
  Cache: array[0..KEYS_COUNT - 1] of Int64;
  CacheLock: TSlimReaderWriterLock;
  TradeChannel: TChannel<TTradeEvent>;
  ConsumerTask: ITask;
  ConsumedTrades: Int64 = 0;
  ConsumerXor: QWord = 0;
  TotalReadSum: Int64 = 0;
  T0, Took: QWord;
  I: Integer;

function ComputeRiskHash(Val: Int64; Iter: Integer): QWord; inline;
var
  H: QWord;
  S: Integer;
begin
  H := QWord(Val) xor QWord(Iter);
  for S := 1 to 30 do
    H := H * 6364136223846793005 + 1442695040888963407;
  Result := H;
end;

procedure RunConsumer;
var
  Ev: TTradeEvent;
begin
  for Ev in TradeChannel do
  begin
    Inc(ConsumedTrades);
    ConsumerXor := ConsumerXor xor Ev.Checksum;
  end;
end;

begin
  Writeln('=== Modern Free Pascal (MFPC): TSlimRWLock + TChannel + TParallel ===');

  for I := 0 to KEYS_COUNT - 1 do
    Cache[I] := (I + 1) * 100;

  CacheLock := TSlimReaderWriterLock.Create;
  TradeChannel := TChannel<TTradeEvent>.Create(50000);

  ConsumerTask := TTask.Run(@RunConsumer);

  T0 := GetTickCount64;

  TParallel.&For(0, NUM_WORKERS - 1,
    procedure(WorkerIdx: Integer)
    var
      ChunkSize, StartI, EndI, I, KeyId: Integer;
      Val: Int64;
      LocalReadSum: Int64;
      Ev: TTradeEvent;
    begin
      ChunkSize := TOTAL_OPS div NUM_WORKERS;
      StartI := WorkerIdx * ChunkSize;
      if WorkerIdx = NUM_WORKERS - 1 then
        EndI := TOTAL_OPS - 1
      else
        EndI := (WorkerIdx + 1) * ChunkSize - 1;

      LocalReadSum := 0;
      for I := StartI to EndI do
      begin
        KeyId := I mod KEYS_COUNT;
        if (I mod 10 <> 0) then
        begin
          // 90% Fast Concurrent Reads: TSlimReaderWriterLock allows all 12 cores to read simultaneously
          CacheLock.BeginRead;
          Val := Cache[KeyId];
          CacheLock.EndRead;

          Inc(LocalReadSum, Val xor (I and 15));
        end
        else
        begin
          // 10% Exclusive Writes + Event Streaming via CSP TChannel
          CacheLock.BeginWrite;
          Cache[KeyId] := Val + (I mod 50);
          Val := Cache[KeyId];
          CacheLock.EndWrite;

          Ev.KeyId := KeyId;
          Ev.Price := Val;
          Ev.Checksum := ComputeRiskHash(Val, I);
          TradeChannel.Send(Ev);
        end;
      end;
      InterlockedExchangeAdd64(TotalReadSum, LocalReadSum);
    end);

  TradeChannel.Close;
  ConsumerTask.Wait;

  Took := GetTickCount64 - T0;

  Writeln('Processed ', TOTAL_OPS, ' ops in: ', Took, ' ms');
  Writeln('Throughput: ', (TOTAL_OPS / (Took / 1000.0)):0:1, ' ops/sec');
  Writeln('Consumed trade events: ', ConsumedTrades, ', Consumer XOR: ', ConsumerXor);
  Writeln('Total read sum: ', TotalReadSum);

  TradeChannel.Free;
  CacheLock.Free;
end.
