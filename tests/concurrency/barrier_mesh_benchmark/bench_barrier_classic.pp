program bench_barrier_classic;
{$mode objfpc}{$H+}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, Classes, syncobjs;

const
  ROWS = 1000;
  COLS = 2000;
  NUM_WORKERS = 12;
  TOTAL_PHASES = 50;

type
  TGrid = array of array of Integer;

  TClassicBarrier = class
  private
    FLock: TCriticalSection;
    FPhaseEvents: array[0..1] of PRTLEvent;
    FTotal: Integer;
    FCount: Integer;
    FPhase: Integer;
  public
    constructor Create(ATotal: Integer);
    destructor Destroy; override;
    procedure SignalAndWait;
  end;

constructor TClassicBarrier.Create(ATotal: Integer);
begin
  FLock := TCriticalSection.Create;
  FPhaseEvents[0] := RTLEventCreate;
  FPhaseEvents[1] := RTLEventCreate;
  FTotal := ATotal;
  FCount := 0;
  FPhase := 0;
end;

destructor TClassicBarrier.Destroy;
begin
  RTLEventDestroy(FPhaseEvents[0]);
  RTLEventDestroy(FPhaseEvents[1]);
  FLock.Free;
  inherited Destroy;
end;

procedure TClassicBarrier.SignalAndWait;
var
  CurrP, NextP: Integer;
begin
  FLock.Acquire;
  CurrP := FPhase and 1;
  Inc(FCount);
  if FCount = FTotal then
  begin
    FCount := 0;
    Inc(FPhase);
    NextP := FPhase and 1;
    RTLEventResetEvent(FPhaseEvents[NextP]);
    RTLEventSetEvent(FPhaseEvents[CurrP]);
    FLock.Release;
    Exit;
  end;
  FLock.Release;

  while (FPhase and 1) = CurrP do
  begin
    RTLEventWaitFor(FPhaseEvents[CurrP]);
    RTLEventSetEvent(FPhaseEvents[CurrP]);
  end;
end;

var
  GridA, GridB: TGrid;
  CurrGrid, NextGrid: ^TGrid;
  Barrier: TClassicBarrier;
  T0, Took: QWord;
  TotalChecksum: Int64 = 0;
  R, C: Integer;

type
  TWorkerThread = class(TThread)
  private
    FWorkerIdx: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AIdx: Integer);
  end;

constructor TWorkerThread.Create(AIdx: Integer);
begin
  FWorkerIdx := AIdx;
  inherited Create(False);
end;

procedure TWorkerThread.Execute;
var
  RowsPerWorker, StartRow, EndRow: Integer;
  Phase, R, C: Integer;
  SumNeighbors: Integer;
  Tmp: ^TGrid;
begin
  RowsPerWorker := (ROWS - 2) div NUM_WORKERS;
  StartRow := 1 + FWorkerIdx * RowsPerWorker;
  if FWorkerIdx = NUM_WORKERS - 1 then
    EndRow := ROWS - 2
  else
    EndRow := StartRow + RowsPerWorker - 1;

  for Phase := 1 to TOTAL_PHASES do
  begin
    for R := StartRow to EndRow do
    begin
      for C := 1 to COLS - 2 do
      begin
        SumNeighbors := CurrGrid^[R - 1][C] + CurrGrid^[R + 1][C] +
                        CurrGrid^[R][C - 1] + CurrGrid^[R][C + 1];
        NextGrid^[R][C] := SumNeighbors div 4;
      end;
    end;

    // Classic barrier synchronization
    Barrier.SignalAndWait;

    // In classic, thread 0 manually swaps
    if FWorkerIdx = 0 then
    begin
      Tmp := CurrGrid;
      CurrGrid := NextGrid;
      NextGrid := Tmp;
    end;

    // Second barrier to ensure swap is visible to all before next phase
    Barrier.SignalAndWait;
  end;
end;

var
  Workers: array[0..NUM_WORKERS - 1] of TWorkerThread;

begin
  Writeln('=== Classic Free Pascal: 2D Numerical Mesh with Custom Barrier ===');
  Writeln('Grid size: ', ROWS, ' x ', COLS, ' = ', ROWS * COLS, ' cells');
  Writeln('Total phases: ', TOTAL_PHASES, ' (', Int64(ROWS) * COLS * TOTAL_PHASES, ' total cell updates across ', NUM_WORKERS, ' workers)');

  SetLength(GridA, ROWS, COLS);
  SetLength(GridB, ROWS, COLS);

  for C := 0 to COLS - 1 do
  begin
    GridA[0][C] := 10000;
    GridA[ROWS - 1][C] := 10000;
    GridB[0][C] := 10000;
    GridB[ROWS - 1][C] := 10000;
  end;

  for R := 450 to 550 do
    for C := 950 to 1050 do
      GridA[R][C] := 50000;

  CurrGrid := @GridA;
  NextGrid := @GridB;

  Barrier := TClassicBarrier.Create(NUM_WORKERS);

  T0 := GetTickCount64;

  for R := 0 to NUM_WORKERS - 1 do
    Workers[R] := TWorkerThread.Create(R);

  for R := 0 to NUM_WORKERS - 1 do
  begin
    Workers[R].WaitFor;
    Workers[R].Free;
  end;

  Took := GetTickCount64 - T0;

  for R := 0 to ROWS - 1 do
    for C := 0 to COLS - 1 do
      Inc(TotalChecksum, CurrGrid^[R][C]);

  Writeln('Completed ', TOTAL_PHASES, ' lockstep phases in: ', Took, ' ms');
  Writeln('Throughput: ', (Double(ROWS * COLS * TOTAL_PHASES) / (Took / 1000.0)):0:1, ' cell-updates/sec');
  Writeln('Final grid energy checksum: ', TotalChecksum);

  Barrier.Free;
end.
