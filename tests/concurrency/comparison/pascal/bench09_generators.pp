program bench09_generators;
{$mode objfpc}{$H+}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, async.generator;

const
  TotalCount = 100000;

type
  TInt64Gen = specialize TGenerator<Int64>;

procedure ProducerCount(const Yield: TInt64Gen.TYieldProc);
var
  I: Integer;
begin
  for I := 1 to TotalCount do
    Yield(I);
end;

var
  Gen: TInt64Gen;
  Sum: Int64 = 0;
  Val: Int64;
  T0, Took: QWord;
begin
  Writeln('=== Benchmark 9: Sequence Generators with Yield ===');
  T0 := GetTickCount64;

  Gen := TInt64Gen.Create(@ProducerCount);
  for Val in Gen do
    Sum := Sum + Val;

  Took := GetTickCount64 - T0;

  Writeln('Generated and consumed ', TotalCount, ' values in: ', Took, ' ms');
  Writeln('Computed sum: ', Sum);

  Gen.Free;

  { Sum of 1..100000 = 5000050000 }
  if (Sum = 5000050000) then
    Writeln('BENCHMARK 9 PASSED')
  else
    Halt(1);
end.
