{ %FAIL }
{ an interpolated string ends at the end of the line }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
program tinterp12;
var
  S: string;
begin
  S := $'abc
def';
end.
