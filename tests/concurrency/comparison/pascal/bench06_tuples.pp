program bench06_tuples;
{$mode objfpc}{$H+}
{$modeswitch tuples}

uses
  SysUtils;

type
  TStatsTuple = (Count: Integer, Sum: Int64);

function ComputeStats(Limit: Integer): TStatsTuple;
var
  I: Integer;
  S: Int64;
begin
  S := 0;
  for I := 1 to Limit do
    Inc(S, I);
  Result := (Limit, S);
end;

var
  T0, Took: QWord;
  I: Integer;
  X, Y: Integer;
  Stats: TStatsTuple;
  TotalSum: Int64;
begin
  Writeln('=== Benchmark 6: Tuples and Deconstruction Performance ===');
  T0 := GetTickCount64;

  { 1. Function returning tuple and deconstructing }
  Stats := ComputeStats(1000);
  var (C, S) := Stats;

  { 2. 10,000,000 parallel swaps without temporary variables }
  X := 10;
  Y := 20;
  for I := 1 to 10000000 do
  begin
    (X, Y) := (Y, X);
  end;

  Took := GetTickCount64 - T0;

  Writeln('Tuple deconstruction: Count = ', C, ', Sum = ', S);
  Writeln('Swapped X = ', X, ', Y = ', Y);
  Writeln('10,000,000 tuple swap operations took: ', Took, ' ms');

  if (C = 1000) and (S = 500500) and (X = 10) and (Y = 20) then
    Writeln('BENCHMARK 6 PASSED')
  else
    Halt(1);
end.

