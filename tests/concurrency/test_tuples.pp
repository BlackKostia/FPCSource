program test_tuples;

{$mode objfpc}{$H+}
{$modeswitch tuples}
{$modeswitch arrowfunctions}

uses
  SysUtils;

var
  TestsPassed: Integer = 0;
  TestsFailed: Integer = 0;

procedure AssertTrue(const Msg: string; Condition: Boolean);
begin
  if Condition then
  begin
    Inc(TestsPassed);
    Writeln('  [PASS] ', Msg);
  end
  else
  begin
    Inc(TestsFailed);
    Writeln('  [FAIL] ', Msg);
  end;
end;

{ 1. Function returning positional tuple (Integer, Integer) }
function DivRem(A, B: Integer): (Integer, Integer);
begin
  Result := (Integer(A div B), Integer(A mod B));
end;

{ 2. Function returning named tuple (Count: Integer, Sum: Int64) }
function CountAndSumPrimes(Limit: Integer): (Count: Integer, Sum: Int64);
var
  I, J: Integer;
  IsPrime: Boolean;
  C: Integer;
  S: Int64;
begin
  C := 0;
  S := 0;
  for I := 2 to Limit do
  begin
    IsPrime := True;
    for J := 2 to Trunc(Sqrt(I)) do
    begin
      if (I mod J) = 0 then
      begin
        IsPrime := False;
        break;
      end;
    end;
    if IsPrime then
    begin
      Inc(C);
      Inc(S, I);
    end;
  end;
  Result := (C, S);
end;

{ 3. Function taking tuple as parameter }
function FormatPerson(P: (Name: string, Age: Integer)): string;
begin
  Result := P.Name + ' is ' + IntToStr(P.Age) + ' years old';
end;

procedure TestBasicTuples;
var
  Q, R: Integer;
begin
  Writeln('--- TestBasicTuples ---');
  (Q, R) := DivRem(10, 3);
  AssertTrue('DivRem Q = 3', Q = 3);
  AssertTrue('DivRem R = 1', R = 1);
end;

procedure TestInlineVarDeconstruction;
begin
  Writeln('--- TestInlineVarDeconstruction ---');
  // var (A, B) := Expr
  var (C, S) := CountAndSumPrimes(10); // primes: 2, 3, 5, 7 -> count 4, sum 17
  AssertTrue('Primes count = 4', C = 4);
  AssertTrue('Primes sum = 17', S = 17);

  // (var A, var B) := Expr
  (var Greeting, var Answer) := ('Hello', 42);
  AssertTrue('Greeting = Hello', Greeting = 'Hello');
  AssertTrue('Answer = 42', Answer = 42);
end;

procedure TestSwapWithoutTemp;
var
  X, Y: Integer;
begin
  Writeln('--- TestSwapWithoutTemp ---');
  X := 10;
  Y := 20;
  (X, Y) := (Y, X);
  AssertTrue('Swap X = 20', X = 20);
  AssertTrue('Swap Y = 10', Y = 10);

  // 3-way cyclic swap
  (var A, var B, var C) := (1, 2, 3);
  (A, B, C) := (C, A, B);
  AssertTrue('Cyclic swap A = 3', A = 3);
  AssertTrue('Cyclic swap B = 1', B = 1);
  AssertTrue('Cyclic swap C = 2', C = 2);
end;

procedure TestManagedTypes;
begin
  Writeln('--- TestManagedTypes ---');
  var (S1, S2) := ('Free', 'Pascal');
  AssertTrue('S1 = Free', S1 = 'Free');
  AssertTrue('S2 = Pascal', S2 = 'Pascal');

  // Reassignment with managed types
  (S1, S2) := (S2, S1);
  AssertTrue('Swapped S1 = Pascal', S1 = 'Pascal');
  AssertTrue('Swapped S2 = Free', S2 = 'Free');
end;

procedure TestFieldAccess;
var
  NamedTup: (Count: Integer, Sum: Int64);
  PosTup: (Integer, string);
begin
  Writeln('--- TestFieldAccess ---');
  NamedTup := (42, 9999999999);
  AssertTrue('Named access .Count', NamedTup.Count = 42);
  AssertTrue('Named access .Sum', NamedTup.Sum = 9999999999);
  AssertTrue('Positional fallback .Item1', NamedTup.Item1 = 42);
  AssertTrue('Positional fallback .Item2', NamedTup.Item2 = 9999999999);

  PosTup := (100, 'items');
  AssertTrue('Positional .Item1', PosTup.Item1 = 100);
  AssertTrue('Positional .Item2', PosTup.Item2 = 'items');
end;

procedure TestTupleAsParameter;
var
  Res: string;
begin
  Writeln('--- TestTupleAsParameter ---');
  Res := FormatPerson(('Bob', 25));
  AssertTrue('FormatPerson', Res = 'Bob is 25 years old');
end;

procedure TestStructuralCompatibility;
var
  T1: (X: Integer, Y: Integer);
  T2: (Integer, Integer);
begin
  Writeln('--- TestStructuralCompatibility ---');
  T1 := (5, 10);
  T2 := T1; // Structural assignment between named and positional tuples
  AssertTrue('Structural copy Item1', T2.Item1 = 5);
  AssertTrue('Structural copy Item2', T2.Item2 = 10);
end;

begin
  Writeln('=== Running Tuples Test Suite ===');
  TestBasicTuples;
  TestInlineVarDeconstruction;
  TestSwapWithoutTemp;
  TestManagedTypes;
  TestFieldAccess;
  TestTupleAsParameter;
  TestStructuralCompatibility;

  Writeln('=================================');
  Writeln('Passed: ', TestsPassed, ', Failed: ', TestsFailed);
  if TestsFailed > 0 then
    Halt(1)
  else
    Writeln('All tuple tests passed successfully!');
end.

