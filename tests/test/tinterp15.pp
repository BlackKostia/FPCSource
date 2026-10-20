{ %FAIL }
{ a record cannot be written }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
program tinterp15;
type
  TRec = record
    X: Integer;
  end;
var
  S: string;
  R: TRec;
begin
  S := $'{R}';
end.
