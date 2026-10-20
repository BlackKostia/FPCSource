{ %FAIL }
{ an unterminated expression }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
program tinterp7;
var
  S: string;
  X: Integer;
begin
  S := $'a{X';
end.
