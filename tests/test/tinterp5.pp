{ %FAIL }
{ an empty expression }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
program tinterp5;
var
  S: string;
begin
  S := $'a{}b';
end.
