{ %FAIL }
{ an expression is not a constant }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
program tinterp11;
var
  X: Integer;
const
  C = $'{X}';
begin
end.
