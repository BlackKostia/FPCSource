program bench_exchange_modern;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
{$modeswitch implicitgenerics}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, SyncObjs, System.Threading;

const
  TOTAL_TRANSACTIONS = 1000000;
  NUM_PRODUCERS = 6;
  NUM_WORKERS = 6;
  BUFFER_CAPACITY = 50000;

type
  TTransaction = record
    TxId: Int64;
    AccountFrom: Integer;
    AccountTo: Integer;
    Amount: Int64;
    Timestamp: QWord;
  end;

  TConfirmation = record
    TxId: Int64;
    Status: Integer;
    Fee: Int64;
    Signature: QWord;
  end;

var
  InboundChan: TChannel<TTransaction>;
  OutboundChan: TChannel<TConfirmation>;
  
  ProducerTasks: array[0..NUM_PRODUCERS - 1] of ITask;
  WorkerTasks: array[0..NUM_WORKERS - 1] of ITask;
  AuditTask: ITask;

  ProducerCD: TCountdownEvent;
  WorkerCD: TCountdownEvent;

  TotalConfirmed: Int64 = 0;
  TotalFees: Int64 = 0;
  AuditChecksum: QWord = 0;
  T0, Took: QWord;
  I: Integer;

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

procedure RunProducer(ProdIdx: Integer);
var
  Chunk, StartI, EndI, I: Integer;
  Tx: TTransaction;
begin
  Chunk := TOTAL_TRANSACTIONS div NUM_PRODUCERS;
  StartI := ProdIdx * Chunk + 1;
  if ProdIdx = NUM_PRODUCERS - 1 then
    EndI := TOTAL_TRANSACTIONS
  else
    EndI := (ProdIdx + 1) * Chunk;

  for I := StartI to EndI do
  begin
    Tx.TxId := I;
    Tx.AccountFrom := (I mod 10000) + 1;
    Tx.AccountTo := ((I + 42) mod 10000) + 1;
    Tx.Amount := (I mod 5000) + 10;
    Tx.Timestamp := GetTickCount64;
    InboundChan.Send(Tx);
  end;

  if ProducerCD.Signal then
    InboundChan.Close;
end;

procedure RunWorker;
var
  Tx: TTransaction;
  Conf: TConfirmation;
begin
  for Tx in InboundChan do
  begin
    Conf.TxId := Tx.TxId;
    Conf.Status := 1;
    Conf.Fee := (Tx.Amount * 15) div 10000; // 0.15% fee
    Conf.Signature := ComputeHash(Tx.TxId, Tx.Amount);
    OutboundChan.Send(Conf);
  end;

  if WorkerCD.Signal then
    OutboundChan.Close;
end;

procedure RunAuditor;
var
  Conf: TConfirmation;
begin
  for Conf in OutboundChan do
  begin
    Inc(TotalConfirmed);
    Inc(TotalFees, Conf.Fee);
    AuditChecksum := AuditChecksum xor Conf.Signature;
  end;
end;

function CreateProducerTask(Idx: Integer): ITask;
begin
  Result := TTask.Run(procedure
    begin
      RunProducer(Idx);
    end);
end;

begin
  Writeln('=== Modern Free Pascal: Pipeline Data Exchange (1,000,000 txs) ===');
  Writeln('Producers: ', NUM_PRODUCERS, ', Workers: ', NUM_WORKERS, ', Auditor: 1');

  InboundChan := TChannel<TTransaction>.Create(BUFFER_CAPACITY);
  OutboundChan := TChannel<TConfirmation>.Create(BUFFER_CAPACITY);

  ProducerCD := TCountdownEvent.Create(NUM_PRODUCERS);
  WorkerCD := TCountdownEvent.Create(NUM_WORKERS);

  T0 := GetTickCount64;

  // 1. Start Auditor
  AuditTask := TTask.Run(@RunAuditor);

  // 2. Start Workers
  for I := 0 to NUM_WORKERS - 1 do
    WorkerTasks[I] := TTask.Run(@RunWorker);

  // 3. Start Producers
  for I := 0 to NUM_PRODUCERS - 1 do
    ProducerTasks[I] := CreateProducerTask(I);

  // Wait for pipeline completion
  AuditTask.Wait;

  Took := GetTickCount64 - T0;

  Writeln('Successfully processed & exchanged ', TotalConfirmed, ' transactions!');
  Writeln('Execution time: ', Took, ' ms');
  Writeln('Throughput: ', (TOTAL_TRANSACTIONS / (Took / 1000.0)):0:1, ' tx/sec');
  Writeln('Total data transfers: ', TotalConfirmed * 2, ' items across threads');
  Writeln('Total fees: $', TotalFees div 100, '.', TotalFees mod 100);
  Writeln('Audit checksum: ', AuditChecksum);

  ProducerCD.Free;
  WorkerCD.Free;
  InboundChan.Free;
  OutboundChan.Free;
end.
