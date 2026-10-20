{ %OPT=-gh }
{ {$modeswitch interpolation}: $'...{Expr}...' with the formatting of
  WriteStr (width and precision), escapes, nesting, constants }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
program tinterp1;

uses
  SysUtils;

type
  TColor = (Red, Green, Blue);

  TOrder = record
    Id: Integer;
    Customer: string;
    Total: Double;
  end;

const
  { without expressions the interpolated string is a constant }
  Plain = $'plain {{text}}';

var
  Order: TOrder;
  Items: array of string;
  I: Integer;
  Big: Int64;
  U: QWord;
  C: Char;
  B: Boolean;
  Color: TColor;
  W: Integer;
  S, T: string;
  Sh: ShortString;

procedure Check(const Got, Expected: string; Code: Integer);
begin
  if Got <> Expected then
    begin
      WriteLn('failed ', Code, ': got "', Got, '" expected "', Expected, '"');
      Halt(Code);
    end;
end;

function Twice(X: Integer): Integer;
begin
  Result := X * 2;
end;

function Describe(const Name: string; N: Integer): string;
begin
  Result := Name + '=' + IntToStr(N);
end;

begin
  Order.Id := 1042;
  Order.Customer := 'Olena';
  Order.Total := 1234.5;
  Items := ['tea', 'coffee'];
  I := -7;
  Big := 1234567890123;
  U := High(QWord);
  C := 'z';
  B := True;
  Color := Green;
  W := 6;

  Check($'Order #{Order.Id} from {Order.Customer}: {Order.Total:0:2}',
    'Order #1042 from Olena: 1234.50', 1);
  Check($'{Length(Items)} items, first: {Items[0]}', '2 items, first: tea', 2);
  Check($'{I} {Big} {U}', '-7 1234567890123 18446744073709551615', 3);
  Check($'{C}{B}{Color}', 'zTRUEGreen', 4);
  { width and precision, also as expressions }
  Check($'|{Order.Id:6}|{Order.Customer:8}|{Order.Total:10:1}|', '|  1042|   Olena|    1234.5|', 5);
  Check($'|{I:W}|{Order.Total:W + 4:W - 4}|', '|    -7|   1234.50|', 6);
  { a real without a specifier is written like WriteLn does }
  WriteStr(T, Order.Total);
  Check($'{Order.Total}', T, 7);
  { function calls and string literals in the expressions }
  Check($'{Twice(21)} {UpperCase('abc')} {Describe('n', 3)}', '42 ABC n=3', 8);
  Check($'{IntToHex(Order.Id, 4)}', '0412', 9);
  { escapes: doubled braces and apostrophes }
  Check($'{{x}} ''{Order.Customer}'' }}', '{x} ''Olena'' }', 10);
  { empty, plain and a single character }
  Check($'', '', 11);
  Check($'abc', 'abc', 12);
  Check($'a', 'a', 13);
  Check(Plain, 'plain {text}', 14);
  { only an expression }
  Check($'{Order.Customer}', 'Olena', 15);
  Check($'{I}', '-7', 16);
  { adjacent expressions }
  Check($'{I}{I}{Order.Customer}{C}', '-7-7Olenaz', 17);
  { nested interpolated strings }
  Check($'<{$'[{Order.Id}]'}>', '<[1042]>', 18);
  { the result is an ordinary string }
  S := $'Id={Order.Id}' + ', ' + $'{Order.Customer}';
  Check(S, 'Id=1042, Olena', 19);
  Check(UpperCase($'{Order.Customer}!'), 'OLENA!', 20);
  Check(IntToStr(Length($'{Order.Id}')), '4', 21);
  { in a loop }
  S := '';
  for I := 1 to 3 do
    S := S + $'[{I}:{I * I}]';
  Check(S, '[1:1][2:4][3:9]', 22);
  { in an exception message }
  try
    raise Exception.Create($'Order #{Order.Id}: not enough funds ({Order.Total:0:2})');
  except
    on E: Exception do
      Check(E.Message, 'Order #1042: not enough funds (1234.50)', 23);
  end;
  { assigned to a ShortString }
  Sh := $'{Order.Customer}-{Order.Id}';
  Check(Sh, 'Olena-1042', 24);
  { a long result }
  S := $'{StringOfChar('x', 300)}{Order.Id}';
  Check(IntToStr(Length(S)), '304', 25);
  { hexadecimal constants are not changed by the mode switch }
  Check(IntToStr($FF + $10), '271', 26);
  Check($'{$FF}', '255', 27);
  WriteLn($'ok');
end.
