{ %FAIL }
{ without the mode switch $'...' is not a string }
{$mode objfpc}{$H+}
program tinterp4;
var
  S: string;
begin
  S := $'abc';
end.
