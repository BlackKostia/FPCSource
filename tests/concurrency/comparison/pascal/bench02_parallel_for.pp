program bench02_parallel_for;
{$mode objfpc}{$H+}
{$modeswitch anonymousfunctions}
{$modeswitch arrowfunctions}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, SyncObjs, System.Threading;

const
  N = 1000000;

var
  Data: array of Integer;
  TotalMatches: Int64 = 0;
  T0, Took: QWord;
  I: Integer;
begin
  Writeln('=== Benchmark 2: TParallel.For CPU Workload ===');
  SetLength(Data, N);
  for I := 0 to N - 1 do
    Data[I] := I;

  T0 := GetTickCount64;

  { Parallel map/filter over 1,000,000 elements }
  TParallel.&For(0, N - 1,
    procedure(Idx: Integer)
    var
      V: Integer;
    begin
      V := Data[Idx];
      { Simulate mathematical work }
      if ((V xor 1234567) mod 1000 = 0) then
        InterlockedIncrement64(TotalMatches);
    end);

  Took := GetTickCount64 - T0;

  Writeln('Processed ', N, ' items in parallel in: ', Took, ' ms');
  Writeln('Total matches found: ', TotalMatches);
  if (TotalMatches = 1001) then
    Writeln('BENCHMARK 2 PASSED')
  else
    Halt(1);
end.
