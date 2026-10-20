{ %OPT=-gh }
{ {$modeswitch interpolation}: the string type of the result follows the
  mode (UnicodeString, ShortString), UTF-8 source code page }
{$mode objfpc}{$H+}
{$codepage utf8}
{$modeswitch interpolation}
{$modeswitch unicodestrings}
program tinterp3;

{$ifdef unix}
uses
  cwstring;
{$endif}

var
  Name: UnicodeString;
  N: Integer;
  A: AnsiString;

procedure Check(const Got, Expected: UnicodeString; Code: Integer);
begin
  if Got <> Expected then
    begin
      WriteLn('failed ', Code);
      Halt(Code);
    end;
end;

procedure ShortStrings;
{$H-}
var
  S: ShortString;
  K: Integer;
begin
  K := 5;
  S := $'short {K}';
  if S <> 'short 5' then
    Halt(20);
end;
{$H+}

begin
  Name := 'Олена';
  N := 3;
  { UnicodeString with modeswitch unicodestrings }
  Check($'Привіт, {Name}! Замовлень: {N}', 'Привіт, Олена! Замовлень: 3', 1);
  Check($'{Name:7}|', '  Олена|', 2);
  A := 'ansi';
  Check($'{A}-{Name}', 'ansi-Олена', 3);
  Check($'ї{{є}}ґ', 'ї{є}ґ', 4);
  ShortStrings;
  WriteLn('ok');
end.
