{ %FAIL }
{ an unknown identifier in an expression }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
program tinterp10;
var
  S: string;
begin
  S := $'{Unknown}';
end.
