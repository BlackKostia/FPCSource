{ %FAIL }
{ a single closing brace }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
program tinterp6;
var
  S: string;
begin
  S := $'a}b';
end.
