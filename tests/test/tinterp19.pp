{ %FAIL }
{ an unterminated multi-line interpolated string }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
{$modeswitch multilinestrings}
program tinterp19;
var
  S: string;
begin
  S := $`a
b;
end.
