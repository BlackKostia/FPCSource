{ an inline variable with an initializer is initialized: reading it must
  not warn "does not seem to be initialized" (the declaration is typechecked
  with the whole block, later statements while they are parsed) }
{$mode objfpc}{$H+}
{$modeswitch inlinevars}
{$modeswitch tuples}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
{$WARN 5036 ERROR}
{$WARN 5037 ERROR}
{$WARN 5057 ERROR}
{$WARN 5058 ERROR}
{$WARN 5089 ERROR}
{$WARN 5090 ERROR}
{$WARN 5091 ERROR}
{$WARN 5092 ERROR}
program tinlinevar26;

procedure Check(Cond: Boolean; Code: Integer);
begin
  if not Cond then
    begin
      WriteLn('failed ', Code);
      Halt(Code);
    end;
end;

procedure UseAfterInit;
begin
  var I := 5;
  Check(I = 5, 1);
  var W: Word := 7;
  Check(W = 7, 2);
  var S: string := 'ab';
  S := S + 'c';
  Check(S = 'abc', 3);
  { assigned by a later statement, not by the declaration }
  var N: Integer;
  N := 4;
  Check(N = 4, 4);
end;

{ the same names, inside a loop, read before any later write }
procedure Partition(Lo, Hi: Integer);
var
  A: array[0..3] of Integer;
begin
  A[0] := 3;
  A[1] := 1;
  A[2] := 4;
  A[3] := 2;
  var Pivot := A[(Lo + Hi) div 2];
  var I := Lo;
  var J := Hi;
  while I <= J do
    begin
      while A[I] < Pivot do
        Inc(I);
      while A[J] > Pivot do
        Dec(J);
      if I <= J then
        begin
          Inc(I);
          Dec(J);
        end;
    end;
  Check(Pivot = 1, 5);
  Check((I = 1) and (J = 0), 6);
end;

function DivRem(A, B: Integer): (Integer, Integer);
begin
  Result := (Integer(A div B), Integer(A mod B));
end;

function Captured: Integer;
type
  TIntFunc = reference to function: Integer;
var
  F: TIntFunc;
begin
  var I := 9;
  F := function: Integer
    begin
      Result := I;
    end;
  Result := F();
end;

begin
  UseAfterInit;
  Partition(0, 3);
  var (Q, R) := DivRem(17, 5);
  Check((Q = 3) and (R = 2), 7);
  var M := 11;
  Check(M = 11, 8);
  Check(Captured = 9, 9);
  WriteLn('ok');
end.
