program bench_barrier_modern;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, SyncObjs, System.Threading;

const
  ROWS = 1000;
  COLS = 2000;
  NUM_WORKERS = 12;
  TOTAL_PHASES = 50;

type
  TGrid = array of array of Integer;

var
  GridA, GridB: TGrid;
  CurrGrid, NextGrid: ^TGrid;
  Barrier: TBarrier;
  Workers: array[0..NUM_WORKERS - 1] of ITask;
  T0, Took: QWord;
  TotalChecksum: Int64 = 0;
  R, C: Integer;

procedure SwapGrids(b: TBarrier);
var
  Tmp: ^TGrid;
begin
  Tmp := CurrGrid;
  CurrGrid := NextGrid;
  NextGrid := Tmp;
end;

procedure RunWorker(WorkerIdx: Integer);
var
  RowsPerWorker, StartRow, EndRow: Integer;
  Phase, R, C: Integer;
  SumNeighbors: Integer;
begin
  RowsPerWorker := (ROWS - 2) div NUM_WORKERS;
  StartRow := 1 + WorkerIdx * RowsPerWorker;
  if WorkerIdx = NUM_WORKERS - 1 then
    EndRow := ROWS - 2
  else
    EndRow := StartRow + RowsPerWorker - 1;

  for Phase := 1 to TOTAL_PHASES do
  begin
    // 5-point discrete Laplacian stencil across 2D grid slice
    for R := StartRow to EndRow do
    begin
      for C := 1 to COLS - 2 do
      begin
        SumNeighbors := CurrGrid^[R - 1][C] + CurrGrid^[R + 1][C] +
                        CurrGrid^[R][C - 1] + CurrGrid^[R][C + 1];
        NextGrid^[R][C] := SumNeighbors div 4;
      end;
    end;

    // Coordinated multi-thread lockstep barrier with post-phase action
    Barrier.SignalAndWait;
  end;
end;

function SpawnWorker(Idx: Integer): ITask;
begin
  Result := TTask.Run(procedure
    begin
      RunWorker(Idx);
    end);
end;

begin
  Writeln('=== Modern Free Pascal: 2D Numerical Mesh with TBarrier ===');
  Writeln('Grid size: ', ROWS, ' x ', COLS, ' = ', ROWS * COLS, ' cells');
  Writeln('Total phases: ', TOTAL_PHASES, ' (', Int64(ROWS) * COLS * TOTAL_PHASES, ' total cell updates across ', NUM_WORKERS, ' workers)');

  SetLength(GridA, ROWS, COLS);
  SetLength(GridB, ROWS, COLS);

  // Initialize Dirichlet boundaries
  for C := 0 to COLS - 1 do
  begin
    GridA[0][C] := 10000;
    GridA[ROWS - 1][C] := 10000;
    GridB[0][C] := 10000;
    GridB[ROWS - 1][C] := 10000;
  end;

  // Initial impulse in center
  for R := 450 to 550 do
    for C := 950 to 1050 do
      GridA[R][C] := 50000;

  CurrGrid := @GridA;
  NextGrid := @GridB;

  Barrier := TBarrier.Create(NUM_WORKERS, @SwapGrids);

  T0 := GetTickCount64;

  for R := 0 to NUM_WORKERS - 1 do
    Workers[R] := SpawnWorker(R);

  for R := 0 to NUM_WORKERS - 1 do
    Workers[R].Wait;

  Took := GetTickCount64 - T0;

  // Compute final checksum
  for R := 0 to ROWS - 1 do
    for C := 0 to COLS - 1 do
      Inc(TotalChecksum, CurrGrid^[R][C]);

  Writeln('Completed ', TOTAL_PHASES, ' lockstep phases in: ', Took, ' ms');
  Writeln('Throughput: ', (Double(ROWS * COLS * TOTAL_PHASES) / (Took / 1000.0)):0:1, ' cell-updates/sec');
  Writeln('Final grid energy checksum: ', TotalChecksum);

  Barrier.Free;
end.
