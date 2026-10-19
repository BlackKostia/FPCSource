program bench_exchange_classic;
{$mode objfpc}{$H+}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, Classes, syncobjs;

const
  TOTAL_TRANSACTIONS = 1000000;
  NUM_PRODUCERS = 6;
  NUM_WORKERS = 6;

type
  PTransaction = ^TTransaction;
  TTransaction = record
    TxId: Int64;
    AccountFrom: Integer;
    AccountTo: Integer;
    Amount: Int64;
    Timestamp: QWord;
    Next: PTransaction;
  end;

  PConfirmation = ^TConfirmation;
  TConfirmation = record
    TxId: Int64;
    Status: Integer;
    Fee: Int64;
    Signature: QWord;
    Next: PConfirmation;
  end;

var
  InboundLock: TCriticalSection;
  InboundHead, InboundTail: PTransaction;
  InboundEvent: PRTLEvent;
  InboundDone: Boolean = False;
  ActiveProducers: Integer = NUM_PRODUCERS;
  ProdLock: TCriticalSection;

  OutboundLock: TCriticalSection;
  OutboundHead, OutboundTail: PConfirmation;
  OutboundEvent: PRTLEvent;
  OutboundDone: Boolean = False;
  ActiveWorkers: Integer = NUM_WORKERS;
  WorkerLock: TCriticalSection;

  TotalConfirmed: Int64 = 0;
  TotalFees: Int64 = 0;
  AuditChecksum: QWord = 0;
  T0, Took: QWord;

function ComputeHash(TxId: Int64; Amount: Int64): QWord; inline;
var
  H: QWord;
  S: Integer;
begin
  H := QWord(TxId) xor (QWord(Amount) shl 16);
  for S := 1 to 20 do
    H := H * 6364136223846793005 + 1442695040888963407;
  Result := H;
end;

procedure PushInbound(const TxId: Int64; FromAcc, ToAcc: Integer; Amt: Int64);
var
  Item: PTransaction;
begin
  New(Item);
  Item^.TxId := TxId;
  Item^.AccountFrom := FromAcc;
  Item^.AccountTo := ToAcc;
  Item^.Amount := Amt;
  Item^.Timestamp := GetTickCount64;
  Item^.Next := nil;

  InboundLock.Acquire;
  try
    if InboundTail <> nil then
      InboundTail^.Next := Item
    else
      InboundHead := Item;
    InboundTail := Item;
  finally
    InboundLock.Release;
  end;
  RTLEventSetEvent(InboundEvent);
end;

function PopInbound(out Item: PTransaction): Boolean;
begin
  Result := False;
  Item := nil;
  InboundLock.Acquire;
  try
    if InboundHead <> nil then
    begin
      Item := InboundHead;
      InboundHead := Item^.Next;
      if InboundHead = nil then
        InboundTail := nil;
      Result := True;
    end;
  finally
    InboundLock.Release;
  end;
end;

procedure PushOutbound(TxId: Int64; Status: Integer; Fee: Int64; Sig: QWord);
var
  Item: PConfirmation;
begin
  New(Item);
  Item^.TxId := TxId;
  Item^.Status := Status;
  Item^.Fee := Fee;
  Item^.Signature := Sig;
  Item^.Next := nil;

  OutboundLock.Acquire;
  try
    if OutboundTail <> nil then
      OutboundTail^.Next := Item
    else
      OutboundHead := Item;
    OutboundTail := Item;
  finally
    OutboundLock.Release;
  end;
  RTLEventSetEvent(OutboundEvent);
end;

function PopOutbound(out Item: PConfirmation): Boolean;
begin
  Result := False;
  Item := nil;
  OutboundLock.Acquire;
  try
    if OutboundHead <> nil then
    begin
      Item := OutboundHead;
      OutboundHead := Item^.Next;
      if OutboundHead = nil then
        OutboundTail := nil;
      Result := True;
    end;
  finally
    OutboundLock.Release;
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

  TWorkerThread = class(TThread)
  protected
    procedure Execute; override;
  end;

  TAuditorThread = class(TThread)
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
  Chunk := TOTAL_TRANSACTIONS div NUM_PRODUCERS;
  StartI := FIdx * Chunk + 1;
  if FIdx = NUM_PRODUCERS - 1 then
    EndI := TOTAL_TRANSACTIONS
  else
    EndI := (FIdx + 1) * Chunk;

  for I := StartI to EndI do
    PushInbound(I, (I mod 10000) + 1, ((I + 42) mod 10000) + 1, (I mod 5000) + 10);

  ProdLock.Acquire;
  try
    Dec(ActiveProducers);
    Remain := ActiveProducers;
  finally
    ProdLock.Release;
  end;

  if Remain = 0 then
  begin
    InboundDone := True;
    RTLEventSetEvent(InboundEvent);
  end;
end;

procedure TWorkerThread.Execute;
var
  Item: PTransaction;
  Remain: Integer;
  Fee: Int64;
  Sig: QWord;
begin
  while True do
  begin
    if PopInbound(Item) then
    begin
      Fee := (Item^.Amount * 15) div 10000;
      Sig := ComputeHash(Item^.TxId, Item^.Amount);
      PushOutbound(Item^.TxId, 1, Fee, Sig);
      Dispose(Item);
    end
    else
    begin
      if InboundDone then
      begin
        // Double check
        if PopInbound(Item) then
        begin
          Fee := (Item^.Amount * 15) div 10000;
          Sig := ComputeHash(Item^.TxId, Item^.Amount);
          PushOutbound(Item^.TxId, 1, Fee, Sig);
          Dispose(Item);
          Continue;
        end;
        Break;
      end;
      RTLEventWaitFor(InboundEvent);
      RTLEventResetEvent(InboundEvent);
    end;
  end;

  WorkerLock.Acquire;
  try
    Dec(ActiveWorkers);
    Remain := ActiveWorkers;
  finally
    WorkerLock.Release;
  end;

  if Remain = 0 then
  begin
    OutboundDone := True;
    RTLEventSetEvent(OutboundEvent);
  end;
end;

procedure TAuditorThread.Execute;
var
  Item: PConfirmation;
begin
  while True do
  begin
    if PopOutbound(Item) then
    begin
      Inc(TotalConfirmed);
      Inc(TotalFees, Item^.Fee);
      AuditChecksum := AuditChecksum xor Item^.Signature;
      Dispose(Item);
    end
    else
    begin
      if OutboundDone then
      begin
        if PopOutbound(Item) then
        begin
          Inc(TotalConfirmed);
          Inc(TotalFees, Item^.Fee);
          AuditChecksum := AuditChecksum xor Item^.Signature;
          Dispose(Item);
          Continue;
        end;
        Break;
      end;
      RTLEventWaitFor(OutboundEvent);
      RTLEventResetEvent(OutboundEvent);
    end;
  end;
end;

var
  Producers: array[0..NUM_PRODUCERS - 1] of TProducerThread;
  Workers: array[0..NUM_WORKERS - 1] of TWorkerThread;
  Auditor: TAuditorThread;
  I: Integer;

begin
  Writeln('=== Classic Free Pascal: Manual Queue Data Exchange (1,000,000 txs) ===');
  Writeln('Producers: ', NUM_PRODUCERS, ', Workers: ', NUM_WORKERS, ', Auditor: 1');

  InboundLock := TCriticalSection.Create;
  InboundEvent := RTLEventCreate;
  InboundHead := nil;
  InboundTail := nil;

  OutboundLock := TCriticalSection.Create;
  OutboundEvent := RTLEventCreate;
  OutboundHead := nil;
  OutboundTail := nil;

  ProdLock := TCriticalSection.Create;
  WorkerLock := TCriticalSection.Create;

  T0 := GetTickCount64;

  Auditor := TAuditorThread.Create(False);

  for I := 0 to NUM_WORKERS - 1 do
    Workers[I] := TWorkerThread.Create(False);

  for I := 0 to NUM_PRODUCERS - 1 do
    Producers[I] := TProducerThread.Create(I);

  for I := 0 to NUM_PRODUCERS - 1 do
  begin
    Producers[I].WaitFor;
    Producers[I].Free;
  end;

  for I := 0 to NUM_WORKERS - 1 do
  begin
    Workers[I].WaitFor;
    Workers[I].Free;
  end;

  Auditor.WaitFor;
  Auditor.Free;

  Took := GetTickCount64 - T0;

  Writeln('Successfully processed & exchanged ', TotalConfirmed, ' transactions!');
  Writeln('Execution time: ', Took, ' ms');
  Writeln('Throughput: ', (TOTAL_TRANSACTIONS / (Took / 1000.0)):0:1, ' tx/sec');
  Writeln('Total data transfers: ', TotalConfirmed * 2, ' items across threads');
  Writeln('Total fees: $', TotalFees div 100, '.', TotalFees mod 100);
  Writeln('Audit checksum: ', AuditChecksum);

  RTLEventDestroy(InboundEvent);
  InboundLock.Free;
  RTLEventDestroy(OutboundEvent);
  OutboundLock.Free;
  ProdLock.Free;
  WorkerLock.Free;
end.

