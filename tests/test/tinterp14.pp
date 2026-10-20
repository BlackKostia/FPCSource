{ %FAIL }
{ a type checked expression: a string is not an integer }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
program tinterp14;
var
  S: string;
  N: Integer;
begin
  N := $'{N}';
end.
