{ %FAIL }
{ overloads of different helpers are not merged: the nearest helper with
  the name wins }
{$mode objfpc}{$H+}
{$modeswitch extensionmethods}
program textmeth6;
type
  THa = type helper for Integer
    function Fmt(const S: string): string;
  end;
  THb = type helper for Integer
    function Fmt(D: Double): string;
  end;
function THa.Fmt(const S: string): string;
begin
  Result := S;
end;
function THb.Fmt(D: Double): string;
begin
  Result := '';
end;
var
  I: Integer;
begin
  I := 1;
  I.Fmt('s');
end.
