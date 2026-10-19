program bench_dag_classic;
{$mode objfpc}{$H+}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, Classes, syncobjs;

const
  TOTAL_MESSAGES = 2000000;
  NUM_PRODUCERS = 4;
  NUM_SHARDS = 4;

type
  PRawMessage = ^TRawMessage;
  TRawMessage = record
    MsgId: Int64;
    AccountId: Integer;
    Amount: Int64;
    Payload: QWord;
    Next: PRawMessage;
  end;

  PEnrichedMessage = ^TEnrichedMessage;
  TEnrichedMessage = record
    MsgId: Int64;
    ShardId: Integer;
    Fee: Int64;
    Signature: QWord;
    Next: PEnrichedMessage;
  end;

  TRawQueue = record
    Lock: TCriticalSection;
    Event: PRTLEvent;
    Head, Tail: PRawMessage;
    Done: Boolean;
  end;

  TEnrichedQueue = record
    Lock: TCriticalSection;
    Event: PRTLEvent;
    Head, Tail: PEnrichedMessage;
    Done: Boolean;
  end;

var
  IngestQ: TRawQueue;
  ShardQs: array[0..NUM_SHARDS - 1] of TRawQueue;
  OutboundQ: TEnrichedQueue;

  ActiveProducers: Integer = NUM_PRODUCERS;
  ProdLock: TCriticalSection;
  ActiveShards: Integer = NUM_SHARDS;
  ShardLock: TCriticalSection;

  TotalAggregated: Int64 = 0;
  TotalFees: Int64 = 0;
  AggregatorChecksum: QWord = 0;
  T0, Took: QWord;

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

procedure InitRawQueue(out Q: TRawQueue);
begin
  Q.Lock := TCriticalSection.Create;
  Q.Event := RTLEventCreate;
  Q.Head := nil;
  Q.Tail := nil;
  Q.Done := False;
end;

procedure FreeRawQueue(var Q: TRawQueue);
begin
  RTLEventDestroy(Q.Event);
  Q.Lock.Free;
end;

procedure InitEnrichedQueue(out Q: TEnrichedQueue);
begin
  Q.Lock := TCriticalSection.Create;
  Q.Event := RTLEventCreate;
  Q.Head := nil;
  Q.Tail := nil;
  Q.Done := False;
end;

procedure FreeEnrichedQueue(var Q: TEnrichedQueue);
begin
  RTLEventDestroy(Q.Event);
  Q.Lock.Free;
end;

procedure PushRaw(var Q: TRawQueue; MsgId: Int64; Acc: Integer; Amt: Int64; Pay: QWord);
var
  Item: PRawMessage;
begin
  New(Item);
  Item^.MsgId := MsgId;
  Item^.AccountId := Acc;
  Item^.Amount := Amt;
  Item^.Payload := Pay;
  Item^.Next := nil;

  Q.Lock.Acquire;
  try
    if Q.Tail <> nil then
      Q.Tail^.Next := Item
    else
      Q.Head := Item;
    Q.Tail := Item;
  finally
    Q.Lock.Release;
  end;
  RTLEventSetEvent(Q.Event);
end;

function PopRaw(var Q: TRawQueue; out Item: PRawMessage): Boolean;
begin
  Result := False;
  Item := nil;
  Q.Lock.Acquire;
  try
    if Q.Head <> nil then
    begin
      Item := Q.Head;
      Q.Head := Item^.Next;
      if Q.Head = nil then
        Q.Tail := nil;
      Result := True;
    end;
  finally
    Q.Lock.Release;
  end;
end;

procedure PushEnriched(var Q: TEnrichedQueue; MsgId: Int64; ShardId: Integer; Fee: Int64; Sig: QWord);
var
  Item: PEnrichedMessage;
begin
  New(Item);
  Item^.MsgId := MsgId;
  Item^.ShardId := ShardId;
  Item^.Fee := Fee;
  Item^.Signature := Sig;
  Item^.Next := nil;

  Q.Lock.Acquire;
  try
    if Q.Tail <> nil then
      Q.Tail^.Next := Item
    else
      Q.Head := Item;
    Q.Tail := Item;
  finally
    Q.Lock.Release;
  end;
  RTLEventSetEvent(Q.Event);
end;

function PopEnriched(var Q: TEnrichedQueue; out Item: PEnrichedMessage): Boolean;
begin
  Result := False;
  Item := nil;
  Q.Lock.Acquire;
  try
    if Q.Head <> nil then
    begin
      Item := Q.Head;
      Q.Head := Item^.Next;
      if Q.Head = nil then
        Q.Tail := nil;
      Result := True;
    end;
  finally
    Q.Lock.Release;
  end;
end;

type
  TProducerThread = class(TThread)
  private
    FIdx: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AIdx: Integer);
  end;

  TRouterThread = class(TThread)
  protected
    procedure Execute; override;
  end;

  TShardWorkerThread = class(TThread)
  private
    FShardIdx: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AShardIdx: Integer);
  end;

  TAggregatorThread = class(TThread)
  protected
    procedure Execute; override;
  end;

constructor TProducerThread.Create(AIdx: Integer);
begin
  FIdx := AIdx;
  inherited Create(False);
end;

procedure TProducerThread.Execute;
var
  Chunk, StartI, EndI, I: Integer;
  Remain: Integer;
begin
  Chunk := TOTAL_MESSAGES div NUM_PRODUCERS;
  StartI := FIdx * Chunk + 1;
  if FIdx = NUM_PRODUCERS - 1 then
    EndI := TOTAL_MESSAGES
  else
    EndI := (FIdx + 1) * Chunk;

  for I := StartI to EndI do
    PushRaw(IngestQ, I, (I mod 100000) + 1, (I mod 5000) + 10, QWord(I * 1337));

  ProdLock.Acquire;
  try
    Dec(ActiveProducers);
    Remain := ActiveProducers;
  finally
    ProdLock.Release;
  end;

  if Remain = 0 then
  begin
    IngestQ.Done := True;
    RTLEventSetEvent(IngestQ.Event);
  end;
end;

procedure TRouterThread.Execute;
var
  Item: PRawMessage;
  ShardIdx: Integer;
begin
  while True do
  begin
    if PopRaw(IngestQ, Item) then
    begin
      ShardIdx := Item^.AccountId mod NUM_SHARDS;
      PushRaw(ShardQs[ShardIdx], Item^.MsgId, Item^.AccountId, Item^.Amount, Item^.Payload);
      Dispose(Item);
    end
    else
    begin
      if IngestQ.Done then
      begin
        if PopRaw(IngestQ, Item) then
        begin
          ShardIdx := Item^.AccountId mod NUM_SHARDS;
          PushRaw(ShardQs[ShardIdx], Item^.MsgId, Item^.AccountId, Item^.Amount, Item^.Payload);
          Dispose(Item);
          Continue;
        end;
        Break;
      end;
      RTLEventWaitFor(IngestQ.Event);
      RTLEventResetEvent(IngestQ.Event);
    end;
  end;

  for ShardIdx := 0 to NUM_SHARDS - 1 do
  begin
    ShardQs[ShardIdx].Done := True;
    RTLEventSetEvent(ShardQs[ShardIdx].Event);
  end;
end;

constructor TShardWorkerThread.Create(AShardIdx: Integer);
begin
  FShardIdx := AShardIdx;
  inherited Create(False);
end;

procedure TShardWorkerThread.Execute;
var
  Item: PRawMessage;
  Fee: Int64;
  Sig: QWord;
  Remain: Integer;
begin
  while True do
  begin
    if PopRaw(ShardQs[FShardIdx], Item) then
    begin
      Fee := (Item^.Amount * 15) div 10000;
      Sig := ComputeRiskSignature(Item^.MsgId, Item^.Amount, FShardIdx);
      PushEnriched(OutboundQ, Item^.MsgId, FShardIdx, Fee, Sig);
      Dispose(Item);
    end
    else
    begin
      if ShardQs[FShardIdx].Done then
      begin
        if PopRaw(ShardQs[FShardIdx], Item) then
        begin
          Fee := (Item^.Amount * 15) div 10000;
          Sig := ComputeRiskSignature(Item^.MsgId, Item^.Amount, FShardIdx);
          PushEnriched(OutboundQ, Item^.MsgId, FShardIdx, Fee, Sig);
          Dispose(Item);
          Continue;
        end;
        Break;
      end;
      RTLEventWaitFor(ShardQs[FShardIdx].Event);
      RTLEventResetEvent(ShardQs[FShardIdx].Event);
    end;
  end;

  ShardLock.Acquire;
  try
    Dec(ActiveShards);
    Remain := ActiveShards;
  finally
    ShardLock.Release;
  end;

  if Remain = 0 then
  begin
    OutboundQ.Done := True;
    RTLEventSetEvent(OutboundQ.Event);
  end;
end;

procedure TAggregatorThread.Execute;
var
  Item: PEnrichedMessage;
begin
  while True do
  begin
    if PopEnriched(OutboundQ, Item) then
    begin
      Inc(TotalAggregated);
      Inc(TotalFees, Item^.Fee);
      AggregatorChecksum := AggregatorChecksum xor Item^.Signature;
      Dispose(Item);
    end
    else
    begin
      if OutboundQ.Done then
      begin
        if PopEnriched(OutboundQ, Item) then
        begin
          Inc(TotalAggregated);
          Inc(TotalFees, Item^.Fee);
          AggregatorChecksum := AggregatorChecksum xor Item^.Signature;
          Dispose(Item);
          Continue;
        end;
        Break;
      end;
      RTLEventWaitFor(OutboundQ.Event);
      RTLEventResetEvent(OutboundQ.Event);
    end;
  end;
end;

var
  Producers: array[0..NUM_PRODUCERS - 1] of TProducerThread;
  Router: TRouterThread;
  Shards: array[0..NUM_SHARDS - 1] of TShardWorkerThread;
  Aggregator: TAggregatorThread;
  I: Integer;

begin
  Writeln('=== Classic Free Pascal: Manual DAG Pipeline (2,000,000 Messages) ===');
  Writeln('Topology: 4 Producers -> IngestQ -> Router -> 4 ShardQs -> 4 Workers -> OutboundQ -> Aggregator');

  InitRawQueue(IngestQ);
  for I := 0 to NUM_SHARDS - 1 do
    InitRawQueue(ShardQs[I]);
  InitEnrichedQueue(OutboundQ);

  ProdLock := TCriticalSection.Create;
  ShardLock := TCriticalSection.Create;

  T0 := GetTickCount64;

  Aggregator := TAggregatorThread.Create(False);

  for I := 0 to NUM_SHARDS - 1 do
    Shards[I] := TShardWorkerThread.Create(I);

  Router := TRouterThread.Create(False);

  for I := 0 to NUM_PRODUCERS - 1 do
    Producers[I] := TProducerThread.Create(I);

  // Wait for all stages
  for I := 0 to NUM_PRODUCERS - 1 do
  begin
    Producers[I].WaitFor;
    Producers[I].Free;
  end;

  Router.WaitFor;
  Router.Free;

  for I := 0 to NUM_SHARDS - 1 do
  begin
    Shards[I].WaitFor;
    Shards[I].Free;
  end;

  Aggregator.WaitFor;
  Aggregator.Free;

  Took := GetTickCount64 - T0;

  Writeln('Successfully processed DAG through all stages: ', TotalAggregated, ' messages');
  Writeln('Total execution time: ', Took, ' ms');
  Writeln('Throughput: ', (TOTAL_MESSAGES / (Took / 1000.0)):0:1, ' msgs/sec');
  Writeln('Total fees: $', TotalFees div 100, '.', TotalFees mod 100);
  Writeln('Aggregator checksum: ', AggregatorChecksum);

  ProdLock.Free;
  ShardLock.Free;
  FreeRawQueue(IngestQ);
  for I := 0 to NUM_SHARDS - 1 do
    FreeRawQueue(ShardQs[I]);
  FreeEnrichedQueue(OutboundQ);
end.

