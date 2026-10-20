{ %FAIL }
{ a class instance cannot be written }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
program tinterp8;
var
  S: string;
  O: TObject;
begin
  O := nil;
  S := $'{O}';
end.
