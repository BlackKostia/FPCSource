{ {$modeswitch extensionmethods}: own helpers for standard types together
  with the helpers of SysUtils and of other units (typehelpers and
  multihelpers) }
{$mode objfpc}{$H+}
{$modeswitch extensionmethods}
program textmeth1;

uses
  { the unit after SysUtils: without multihelpers its string helper would
    hide TStringHelper }
  SysUtils, uextmeth1;

type
  TColor = (Red, Green, Blue);
  TIntArray = array of Integer;
  TPoint2 = record
    X, Y: Integer;
  end;

  TStrHelper = type helper for string
    function Shout: string;
    function Stripped: string;
  end;

  TIntHelper = type helper for Integer
    function IsEven: Boolean;
    function Times(N: Integer): Integer;
  end;

  { a second helper for Integer: both are used }
  TIntHelper2 = type helper for Integer
    function Squared: Integer;
  end;

  TDoubleHelper = type helper for Double
    function Half: Double;
  end;

  TDateHelper = type helper for TDateTime
    function IsWeekend: Boolean;
  end;

  TColorHelper = type helper for TColor
    function Next: TColor;
  end;

  TIntArrayHelper = type helper for TIntArray
    function Sum: Integer;
  end;

  TPointHelper = type helper for TPoint2
    function Len2: Integer;
  end;

  TObjectHelperEx = class helper for TObject
    function Describe: string;
  end;

function TStrHelper.Shout: string;
begin
  Result := UpperCase(Self) + '!';
end;

function TStrHelper.Stripped: string;
begin
  { the method of TStringHelper, the global function needs the unit name }
  Result := Self.Trim + '|' + SysUtils.Trim(Self);
end;

function TIntHelper.IsEven: Boolean;
begin
  Result := not Odd(Self);
end;

function TIntHelper.Times(N: Integer): Integer;
begin
  Result := Self * N;
end;

function TIntHelper2.Squared: Integer;
begin
  Result := Self * Self;
end;

function TDoubleHelper.Half: Double;
begin
  Result := Self / 2;
end;

function TDateHelper.IsWeekend: Boolean;
begin
  Result := DayOfWeek(Self) in [1, 7];
end;

function TColorHelper.Next: TColor;
begin
  if Self = High(TColor) then
    Result := Low(TColor)
  else
    Result := Succ(Self);
end;

function TIntArrayHelper.Sum: Integer;
var
  V: Integer;
begin
  Result := 0;
  for V in Self do
    Inc(Result, V);
end;

function TPointHelper.Len2: Integer;
begin
  Result := X * X + Y * Y;
end;

function TObjectHelperEx.Describe: string;
begin
  Result := 'object ' + ClassName;
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
  S: string;
  I: Integer;
  D: Double;
  Day: TDateTime;
  C: TColor;
  A: TIntArray;
  P: TPoint2;
  O: TObject;

begin
  S := 'hello world';
  I := 6;
  D := 5.0;
  Day := EncodeDate(2026, 10, 24);
  C := Blue;
  A := [1, 2, 3];
  P.X := 3;
  P.Y := 4;

  { own helpers }
  Check(S.Shout = 'HELLO WORLD!', 1);
  Check(I.IsEven and (I.Times(7) = 42), 2);
  Check(I.Squared = 36, 3);
  Check(D.Half = 2.5, 4);
  Check(Day.IsWeekend, 5);
  Check(C.Next = Red, 6);
  Check(A.Sum = 6, 7);
  Check(P.Len2 = 25, 8);
  O := TObject.Create;
  Check(O.Describe = 'object TObject', 9);
  O.Free;
  { the helpers of SysUtils are still available }
  Check(S.ToUpper = 'HELLO WORLD', 10);
  Check(S.Length = 11, 11);
  Check(I.ToString = '6', 12);
  Check(S.PadRight(13) = 'hello world  ', 13);
  { the helpers of another unit }
  Check(S.Words = 2, 14);
  { the same method name in two helpers: the nearest helper wins }
  Check(I.Who = 'unit', 15);
  { helper methods on expressions and results }
  Check(IntToStr(I).Shout = '6!', 16);
  { a helper belongs to its exact type: I + 1 is an Int64 on 64-bit
    targets, the helper for Integer needs a typecast }
  Check(Integer(I + 1).Squared = 49, 17);
  Check(S.Shout.ToLower = 'hello world!', 18);
  Check(' x '.Stripped = 'x|x', 19);
  WriteLn('ok');
end.
