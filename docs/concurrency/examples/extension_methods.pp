(* Methods for standard types ({$modeswitch extensionmethods} = typehelpers
   + multihelpers): own helpers for string, Integer, TDateTime, enumerations
   and arrays next to the helpers of SysUtils.
   See docs/concurrency/language/helpers.md *)
program extension_methods;

{$mode objfpc}{$H+}
{$modeswitch extensionmethods}

uses
  SysUtils;

type
  TWeekday = (Mon, Tue, Wed, Thu, Fri, Sat, Sun);
  TPrices = array of Double;

  TStringEx = type helper for string
    function IsBlank: Boolean;
    function Initials: string;
  end;

  TIntegerEx = type helper for Integer
    function Clamp(Lo, Hi: Integer): Integer;
    function Plural(const One, Many: string): string;
  end;

  TDateTimeEx = type helper for TDateTime
    function IsWeekend: Boolean;
    function DaysUntil(Other: TDateTime): Integer;
  end;

  TWeekdayEx = type helper for TWeekday
    function Name: string;
    function IsWorkday: Boolean;
  end;

  TPricesEx = type helper for TPrices
    function Total: Double;
    function Max: Double;
  end;

function TStringEx.IsBlank: Boolean;
begin
  { in a helper method the methods of all helpers of the type hide global
    routines of the same name: Trim is TStringHelper.Trim here }
  Result := Self.Trim = '';
end;

function TStringEx.Initials: string;
var
  Part: string;
begin
  Result := '';
  for Part in Self.Split([' '], TStringSplitOptions.ExcludeEmpty) do
    Result := Result + UpCase(Part[1]) + '.';
end;

function TIntegerEx.Clamp(Lo, Hi: Integer): Integer;
begin
  if Self < Lo then
    Result := Lo
  else if Self > Hi then
    Result := Hi
  else
    Result := Self;
end;

function TIntegerEx.Plural(const One, Many: string): string;
begin
  if Self = 1 then
    Result := Self.ToString + ' ' + One
  else
    Result := Self.ToString + ' ' + Many;
end;

function TDateTimeEx.IsWeekend: Boolean;
begin
  Result := DayOfWeek(Self) in [1, 7];
end;

function TDateTimeEx.DaysUntil(Other: TDateTime): Integer;
begin
  Result := Trunc(Other) - Trunc(Self);
end;

function TWeekdayEx.Name: string;
const
  Names: array[TWeekday] of string = ('Monday', 'Tuesday', 'Wednesday',
    'Thursday', 'Friday', 'Saturday', 'Sunday');
begin
  Result := Names[Self];
end;

function TWeekdayEx.IsWorkday: Boolean;
begin
  Result := Self < Sat;
end;

function TPricesEx.Total: Double;
var
  P: Double;
begin
  Result := 0;
  for P in Self do
    Result := Result + P;
end;

function TPricesEx.Max: Double;
var
  P: Double;
begin
  Result := 0;
  for P in Self do
    if P > Result then
      Result := P;
end;

var
  Name: string;
  Count: Integer;
  Today, Deadline: TDateTime;
  Day: TWeekday;
  Prices: TPrices;

begin
  Name := '  taras  hryhorovych shevchenko ';
  { own methods and the methods of TStringHelper (SysUtils) together }
  WriteLn(Name.Trim.ToUpper, ' -> ', Name.Initials, ', blank: ', Name.IsBlank);

  Count := 1;
  WriteLn(Count.Plural('file', 'files'), ', ', (Count + 4).ToString);
  Count := 250;
  WriteLn(Count.Clamp(0, 100), ' ', Count.Plural('file', 'files'));

  Today := EncodeDate(2026, 10, 24);
  Deadline := EncodeDate(2026, 12, 31);
  WriteLn('weekend: ', Today.IsWeekend, ', days until the deadline: ', Today.DaysUntil(Deadline));

  for Day in TWeekday do
    if not Day.IsWorkday then
      WriteLn(Day.Name, ' is a day off');

  Prices := [12.5, 99.99, 7.25];
  WriteLn('total: ', Prices.Total:0:2, ', max: ', Prices.Max:0:2);
end.
