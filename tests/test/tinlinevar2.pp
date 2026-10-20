{ {$modeswitch inlinevars}: for var ... := ... to / downto and for var ... in }
{$mode objfpc}{$H+}
{$modeswitch inlinevars}
program tinlinevar2;

uses
  Generics.Collections;

type
  TColor = (Red, Green, Blue);

  { the loop frees the enumerator }
  TCounterEnumerator = class
    FIndex, FLast: Integer;
    function MoveNext: Boolean;
    property Current: Integer read FIndex;
  end;

  TCounter = class
    FLast: Integer;
    function GetEnumerator: TCounterEnumerator;
  end;

function TCounterEnumerator.MoveNext: Boolean;
begin
  Inc(FIndex);
  Result := FIndex <= FLast;
end;

function TCounter.GetEnumerator: TCounterEnumerator;
begin
  Result := TCounterEnumerator.Create;
  Result.FLast := FLast;
end;

procedure Check(Cond: Boolean; Code: Integer);
begin
  if not Cond then
    begin
      WriteLn('failed ', Code);
      Halt(Code);
    end;
end;

var
  Sum: Int64;
  Txt: string;
  Arr: array of Double;
  List: specialize TList<string>;
  Counter: TCounter;
begin
  Sum := 0;
  for var I := 1 to 10 do
    Inc(Sum, I);
  Check(Sum = 55, 1);
  { the same name again in the next loop, another type }
  for var I: Int64 := 10000000000 downto 9999999998 do
    Inc(Sum, I - 9999999990);
  Check(Sum = 55 + 10 + 9 + 8, 2);
  Txt := '';
  for var Ch in 'abc' do
    Txt := Txt + Ch + Ch;
  Check(Txt = 'aabbcc', 3);
  SetLength(Arr, 3);
  Arr[0] := 0.5; Arr[1] := 1.5; Arr[2] := 2;
  var Total := 0.0;
  for var D in Arr do
    Total := Total + D;
  Check(Total = 4, 4);
  Sum := 0;
  for var E in TColor do
    Inc(Sum, Ord(E) + 1);
  Check(Sum = 6, 5);
  Sum := 0;
  for var E in [Red, Blue] do
    Inc(Sum, Ord(E));
  Check(Sum = 2, 6);
  Sum := 0;
  for var N in [10, 20, 30] do
    Inc(Sum, N);
  Check(Sum = 60, 7);
  List := specialize TList<string>.Create;
  List.Add('x');
  List.Add('yz');
  Sum := 0;
  for var Item in List do
    Inc(Sum, Length(Item));
  Check(Sum = 3, 8);
  List.Free;
  Counter := TCounter.Create;
  Counter.FLast := 4;
  Sum := 0;
  for var K in Counter do
    Inc(Sum, K);
  Check(Sum = 10, 9);
  Counter.Free;
  { nested loops }
  Sum := 0;
  for var R := 1 to 3 do
    for var Q := R to 3 do
      Inc(Sum);
  Check(Sum = 6, 10);
  WriteLn('ok');
end.
