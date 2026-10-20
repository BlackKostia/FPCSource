{ %FAIL }
{ assignment to a var section resource in the statement }
{$mode objfpc}
{$modeswitch using}
program tusing7;
var
  R: TObject;
begin
  using R := TObject.Create do
    R := nil;
end.
