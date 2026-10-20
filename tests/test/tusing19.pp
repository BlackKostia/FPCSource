{ %FAIL }
{ the resource variable of a var section must be a variable, not a constant }
{$mode objfpc}
{$modeswitch using}
program tusing19;
procedure P(const R: TObject);
begin
  using R := TObject.Create do
    ;
end;
begin
end.
