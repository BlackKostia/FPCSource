{ %FAIL }
{ an error in an expression on the third line of $`...` }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
{$modeswitch multilinestrings}
program tinterp20;
var
  S: string;
begin
  S := $`a
b
c {Unknown}`;
end.
