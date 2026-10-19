program bench_classic_pascal;
{$mode objfpc}{$H+}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, Classes, syncobjs;

const
  TOTAL_OPS = 2000000;
  KEYS_COUNT = 1000;
  NUM_WORKERS = 12;

type
  PTradeEventItem = ^TTradeEventItem;
  TTradeEventItem = record
    KeyId: Integer;
    Price: Int64;
    Checksum: QWord;
    Next: PTradeEventItem;
  end;

  TWorkerThread = class(TThread)
  private
    FStartI, FEndI: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AStart, AEnd: Integer);
  end;

  TConsumerThread = class(TThread)
  protected
    procedure Execute; override;
  end;

var
  Cache: array[0..KEYS_COUNT - 1] of Int64;
  CacheLock: TCriticalSection;
  QueueLock: TCriticalSection;
  QueueHead, QueueTail: PTradeEventItem;
  QueueEvent: PRTLEvent;
  QueueDone: Boolean = False;

  ConsumedTrades: Int64 = 0;
  ConsumerXor: QWord = 0;
  TotalReadSum: Int64 = 0;
  T0, Took: QWord;
  Workers: array[0..NUM_WORKERS - 1] of TWorkerThread;
  Consumer: TConsumerThread;
  I, ChunkSize: Integer;

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

procedure PushEvent(AKey: Integer; APrice: Int64; ACheck: QWord);
var
  Item: PTradeEventItem;
begin
  New(Item);
  Item^.KeyId := AKey;
  Item^.Price := APrice;
  Item^.Checksum := ACheck;
  Item^.Next := nil;

  QueueLock.Acquire;
  try
    if QueueTail <> nil then
      QueueTail^.Next := Item
    else
      QueueHead := Item;
    QueueTail := Item;
  finally
    QueueLock.Release;
  end;
  RTLEventSetEvent(QueueEvent);
end;

procedure TConsumerThread.Execute;
var
  Item: PTradeEventItem;
begin
  while True do
  begin
    QueueLock.Acquire;
    try
      Item := QueueHead;
      if Item <> nil then
      begin
        QueueHead := Item^.Next;
        if QueueHead = nil then
          QueueTail := nil;
      end;
    finally
      QueueLock.Release;
    end;

    if Item <> nil then
    begin
      Inc(ConsumedTrades);
      ConsumerXor := ConsumerXor xor Item^.Checksum;
      Dispose(Item);
    end
    else
    begin
      if QueueDone then
        Break;
      RTLEventWaitFor(QueueEvent);
      RTLEventResetEvent(QueueEvent);
    end;
  end;
end;

constructor TWorkerThread.Create(AStart, AEnd: Integer);
begin
  FStartI := AStart;
  FEndI := AEnd;
  inherited Create(False);
end;

procedure TWorkerThread.Execute;
var
  I, KeyId: Integer;
  Val: Int64;
  LocalReadSum: Int64;
begin
  LocalReadSum := 0;
  Val := 0;
  for I := FStartI to FEndI do
  begin
    KeyId := I mod KEYS_COUNT;
    if (I mod 10 <> 0) then
    begin
      // In classic Pascal, TCriticalSection serializes ALL readers!
      CacheLock.Acquire;
      try
        Val := Cache[KeyId];
      finally
        CacheLock.Release;
      end;
      Inc(LocalReadSum, Val xor (I and 15));
    end
    else
    begin
      CacheLock.Acquire;
      try
        Cache[KeyId] := Val + (I mod 50);
        Val := Cache[KeyId];
      finally
        CacheLock.Release;
      end;
      PushEvent(KeyId, Val, ComputeRiskHash(Val, I));
    end;
  end;
  InterlockedExchangeAdd64(TotalReadSum, LocalReadSum);
end;

begin
  Writeln('=== Classic Free Pascal: TCriticalSection + TThread + Custom Queue ===');

  for I := 0 to KEYS_COUNT - 1 do
    Cache[I] := (I + 1) * 100;

  CacheLock := TCriticalSection.Create;
  QueueLock := TCriticalSection.Create;
  QueueHead := nil;
  QueueTail := nil;
  QueueEvent := RTLEventCreate;

  Consumer := TConsumerThread.Create(False);

  T0 := GetTickCount64;

  ChunkSize := TOTAL_OPS div NUM_WORKERS;
  for I := 0 to NUM_WORKERS - 1 do
  begin
    if I = NUM_WORKERS - 1 then
      Workers[I] := TWorkerThread.Create(I * ChunkSize, TOTAL_OPS - 1)
    else
      Workers[I] := TWorkerThread.Create(I * ChunkSize, (I + 1) * ChunkSize - 1);
  end;

  for I := 0 to NUM_WORKERS - 1 do
  begin
    Workers[I].WaitFor;
    Workers[I].Free;
  end;

  QueueDone := True;
  RTLEventSetEvent(QueueEvent);
  Consumer.WaitFor;
  Consumer.Free;

  Took := GetTickCount64 - T0;

  Writeln('Processed ', TOTAL_OPS, ' ops in: ', Took, ' ms');
  Writeln('Throughput: ', (TOTAL_OPS / (Took / 1000.0)):0:1, ' ops/sec');
  Writeln('Consumed trade events: ', ConsumedTrades, ', Consumer XOR: ', ConsumerXor);
  Writeln('Total read sum: ', TotalReadSum);

  RTLEventDestroy(QueueEvent);
  QueueLock.Free;
  CacheLock.Free;
end.
