{ %FAIL }
{ a pointer cannot be written }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
program tinterp13;
var
  S: string;
  P: Pointer;
begin
  P := nil;
  S := $'{P}';
end.
