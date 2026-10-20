{ %FAIL }
{ an expression ends on its line }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
{$modeswitch multilinestrings}
program tinterp18;
var
  S: string;
  X: Integer;
begin
  S := $`a {X
} b`;
end.
