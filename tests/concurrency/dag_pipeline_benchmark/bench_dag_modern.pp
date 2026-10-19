program bench_dag_modern;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
{$modeswitch implicitgenerics}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, SyncObjs, System.Threading;

const
  TOTAL_MESSAGES = 2000000;
  NUM_PRODUCERS = 4;
  NUM_SHARDS = 4;
  INGEST_CAPACITY = 50000;
  SHARD_CAPACITY = 25000;
  OUTBOUND_CAPACITY = 50000;

type
  TRawMessage = record
    MsgId: Int64;
    AccountId: Integer;
    Amount: Int64;
    Payload: QWord;
  end;

  TEnrichedMessage = record
    MsgId: Int64;
    ShardId: Integer;
    Fee: Int64;
    Signature: QWord;
  end;

var
  IngestChan: TChannel<TRawMessage>;
  ShardChans: array[0..NUM_SHARDS - 1] of TChannel<TRawMessage>;
  OutboundChan: TChannel<TEnrichedMessage>;

  ProducerTasks: array[0..NUM_PRODUCERS - 1] of ITask;
  RouterTask: ITask;
  ShardTasks: array[0..NUM_SHARDS - 1] of ITask;
  AggregatorTask: ITask;

  ProducerCD: TCountdownEvent;
  ShardCD: TCountdownEvent;

  TotalAggregated: Int64 = 0;
  TotalFees: Int64 = 0;
  AggregatorChecksum: QWord = 0;
  T0, Took: QWord;
  I: Integer;

function ComputeRiskSignature(MsgId, Amount: Int64; ShardId: Integer): QWord; inline;
var
  H: QWord;
  S: Integer;
begin
  H := QWord(MsgId) xor (QWord(Amount) shl 16) xor QWord(ShardId * 7919);
  for S := 1 to 20 do
    H := H * 6364136223846793005 + 1442695040888963407;
  Result := H;
end;

procedure RunProducer(ProdIdx: Integer);
var
  Chunk, StartI, EndI, I: Integer;
  Msg: TRawMessage;
begin
  Chunk := TOTAL_MESSAGES div NUM_PRODUCERS;
  StartI := ProdIdx * Chunk + 1;
  if ProdIdx = NUM_PRODUCERS - 1 then
    EndI := TOTAL_MESSAGES
  else
    EndI := (ProdIdx + 1) * Chunk;

  for I := StartI to EndI do
  begin
    Msg.MsgId := I;
    Msg.AccountId := (I mod 100000) + 1;
    Msg.Amount := (I mod 5000) + 10;
    Msg.Payload := QWord(I * 1337);
    IngestChan.Send(Msg);
  end;

  if ProducerCD.Signal then
    IngestChan.Close;
end;

procedure RunRouter;
var
  Msg: TRawMessage;
  ShardIdx: Integer;
begin
  for Msg in IngestChan do
  begin
    ShardIdx := Msg.AccountId mod NUM_SHARDS;
    ShardChans[ShardIdx].Send(Msg);
  end;

  for ShardIdx := 0 to NUM_SHARDS - 1 do
    ShardChans[ShardIdx].Close;
end;

procedure RunShardWorker(ShardIdx: Integer);
var
  Msg: TRawMessage;
  Enriched: TEnrichedMessage;
begin
  for Msg in ShardChans[ShardIdx] do
  begin
    Enriched.MsgId := Msg.MsgId;
    Enriched.ShardId := ShardIdx;
    Enriched.Fee := (Msg.Amount * 15) div 10000;
    Enriched.Signature := ComputeRiskSignature(Msg.MsgId, Msg.Amount, ShardIdx);
    OutboundChan.Send(Enriched);
  end;

  if ShardCD.Signal then
    OutboundChan.Close;
end;

procedure RunAggregator;
var
  Enriched: TEnrichedMessage;
begin
  for Enriched in OutboundChan do
  begin
    Inc(TotalAggregated);
    Inc(TotalFees, Enriched.Fee);
    AggregatorChecksum := AggregatorChecksum xor Enriched.Signature;
  end;
end;

function SpawnProducer(Idx: Integer): ITask;
begin
  Result := TTask.Run(procedure
    begin
      RunProducer(Idx);
    end);
end;

function SpawnShardWorker(Idx: Integer): ITask;
begin
  Result := TTask.Run(procedure
    begin
      RunShardWorker(Idx);
    end);
end;

begin
  Writeln('=== Modern Free Pascal: DAG Actor Pipeline (2,000,000 Messages) ===');
  Writeln('Topology: 4 Producers -> IngestChan -> Router -> 4 ShardChans -> 4 Workers -> OutboundChan -> Aggregator');

  IngestChan := TChannel<TRawMessage>.Create(INGEST_CAPACITY);
  for I := 0 to NUM_SHARDS - 1 do
    ShardChans[I] := TChannel<TRawMessage>.Create(SHARD_CAPACITY);
  OutboundChan := TChannel<TEnrichedMessage>.Create(OUTBOUND_CAPACITY);

  ProducerCD := TCountdownEvent.Create(NUM_PRODUCERS);
  ShardCD := TCountdownEvent.Create(NUM_SHARDS);

  T0 := GetTickCount64;

  // 1. Aggregator (Fan-In Consumer)
  AggregatorTask := TTask.Run(@RunAggregator);

  // 2. Shard Workers
  for I := 0 to NUM_SHARDS - 1 do
    ShardTasks[I] := SpawnShardWorker(I);

  // 3. Router Dispatcher (Fan-Out)
  RouterTask := TTask.Run(@RunRouter);

  // 4. Ingestion Producers
  for I := 0 to NUM_PRODUCERS - 1 do
    ProducerTasks[I] := SpawnProducer(I);

  // Wait for entire DAG completion
  AggregatorTask.Wait;

  Took := GetTickCount64 - T0;

  Writeln('Successfully processed DAG through all stages: ', TotalAggregated, ' messages');
  Writeln('Total execution time: ', Took, ' ms');
  Writeln('Throughput: ', (TOTAL_MESSAGES / (Took / 1000.0)):0:1, ' msgs/sec');
  Writeln('Total fees: $', TotalFees div 100, '.', TotalFees mod 100);
  Writeln('Aggregator checksum: ', AggregatorChecksum);

  ProducerCD.Free;
  ShardCD.Free;
  IngestChan.Free;
  for I := 0 to NUM_SHARDS - 1 do
    ShardChans[I].Free;
  OutboundChan.Free;
end.

