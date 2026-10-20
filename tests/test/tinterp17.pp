{ %FAIL }
{ $`...` needs the mode switch multilinestrings }
{$mode objfpc}{$H+}
{$modeswitch multilinestrings-}
{$modeswitch interpolation}
program tinterp17;
var
  S: string;
begin
  S := $`a
b`;
end.
