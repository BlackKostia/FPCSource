{ %FAIL }
{ a precision for a string }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
program tinterp9;
var
  S, T: string;
begin
  T := 'x';
  S := $'{T:5:2}';
end.
