program bench_acid_modern;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, SyncObjs, System.Threading;

const
  TOTAL_TXS = 2000000;
  NUM_ACCOUNTS = 500;
  NUM_WORKERS = 12;
  INITIAL_BALANCE: Int64 = 1000000; // $10,000.00 in cents

var
  Balances: array[0..NUM_ACCOUNTS - 1] of Int64;
  AccountLocks: array[0..NUM_ACCOUNTS - 1] of TSlimReaderWriterLock;
  Workers: array[0..NUM_WORKERS - 1] of ITask;
  T0, Took: QWord;
  TotalInquiries: Int64 = 0;
  TotalTransfers: Int64 = 0;
  TotalCasOps: Int64 = 0;
  FinalTotalMoney: Int64 = 0;
  I: Integer;

function Min(A, B: Integer): Integer; inline;
begin
  if A < B then Result := A else Result := B;
end;

function Max(A, B: Integer): Integer; inline;
begin
  if A > B then Result := A else Result := B;
end;

procedure RunWorker(WorkerIdx: Integer);
var
  Chunk, StartI, EndI, I: Integer;
  OpType: Integer;
  AccA, AccB, FirstLock, SecondLock: Integer;
  Amount, OldVal, NewVal, ReadVal: Int64;
  LocalInquiries, LocalTransfers, LocalCasOps: Int64;
begin
  Chunk := TOTAL_TXS div NUM_WORKERS;
  StartI := WorkerIdx * Chunk + 1;
  if WorkerIdx = NUM_WORKERS - 1 then
    EndI := TOTAL_TXS
  else
    EndI := (WorkerIdx + 1) * Chunk;

  LocalInquiries := 0;
  LocalTransfers := 0;
  LocalCasOps := 0;

  for I := StartI to EndI do
  begin
    OpType := I mod 10;
    AccA := (I * 7919) mod NUM_ACCOUNTS;

    if OpType < 7 then
    begin
      // 70% Inquiries: Parallel Read Lock on Account
      AccountLocks[AccA].BeginRead;
      ReadVal := Balances[AccA];
      AccountLocks[AccA].EndRead;
      Inc(LocalInquiries, ReadVal and 1);
    end
    else if OpType < 9 then
    begin
      // 20% Single-Account Direct Update: Lock-Free CAS
      Amount := (I mod 100) + 1;
      repeat
        OldVal := Balances[AccA];
        if (I and 1) = 0 then
          NewVal := OldVal + Amount
        else
          NewVal := OldVal - Amount;
      until InterlockedCompareExchange64(Balances[AccA], NewVal, OldVal) = OldVal;
      Inc(LocalCasOps);
    end
    else
    begin
      // 10% Multi-Account Transfer: Strict Hierarchical Deadlock-Free 2-Lock Acquisition
      AccB := ((I * 1337) + 42) mod NUM_ACCOUNTS;
      if AccA = AccB then
        AccB := (AccA + 1) mod NUM_ACCOUNTS;

      FirstLock := Min(AccA, AccB);
      SecondLock := Max(AccA, AccB);

      AccountLocks[FirstLock].BeginWrite;
      AccountLocks[SecondLock].BeginWrite;
      try
        Amount := (I mod 250) + 10;
        if Balances[AccA] >= Amount then
        begin
          Balances[AccA] := Balances[AccA] - Amount;
          Balances[AccB] := Balances[AccB] + Amount;
        end;
        Inc(LocalTransfers);
      finally
        AccountLocks[SecondLock].EndWrite;
        AccountLocks[FirstLock].EndWrite;
      end;
    end;
  end;

  InterlockedExchangeAdd64(TotalInquiries, LocalInquiries);
  InterlockedExchangeAdd64(TotalTransfers, LocalTransfers);
  InterlockedExchangeAdd64(TotalCasOps, LocalCasOps);
end;

function SpawnWorker(Idx: Integer): ITask;
begin
  Result := TTask.Run(procedure
    begin
      RunWorker(Idx);
    end);
end;

begin
  Writeln('=== Modern Free Pascal: High-Contention ACID Banking Ledger (2,000,000 TXs) ===');
  Writeln('Accounts: ', NUM_ACCOUNTS, ' (Each starting with $', INITIAL_BALANCE div 100, '.00)');
  Writeln('Transactions: ', TOTAL_TXS, ' (70% RWLock Inquiries, 20% Lock-Free CAS, 10% Ordered 2-Lock Transfers)');

  for I := 0 to NUM_ACCOUNTS - 1 do
  begin
    Balances[I] := INITIAL_BALANCE;
    AccountLocks[I] := TSlimReaderWriterLock.Create;
  end;

  T0 := GetTickCount64;

  for I := 0 to NUM_WORKERS - 1 do
    Workers[I] := SpawnWorker(I);

  for I := 0 to NUM_WORKERS - 1 do
    Workers[I].Wait;

  Took := GetTickCount64 - T0;

  for I := 0 to NUM_ACCOUNTS - 1 do
    Inc(FinalTotalMoney, Balances[I]);

  Writeln('Processed ', TOTAL_TXS, ' ACID transactions in: ', Took, ' ms');
  Writeln('Throughput: ', (Double(TOTAL_TXS) / (Took / 1000.0)):0:1, ' tx/sec');
  Writeln('Operations breakdown: Inquiries=', TOTAL_TXS * 7 div 10, ', Transfers=', TotalTransfers, ', CAS Direct Ops=', TotalCasOps);
  Writeln('Final Total Bank Balance: $', FinalTotalMoney div 100, '.', FinalTotalMoney mod 100);

  for I := 0 to NUM_ACCOUNTS - 1 do
    AccountLocks[I].Free;
end.
