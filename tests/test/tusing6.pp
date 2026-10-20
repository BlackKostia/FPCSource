{ %FAIL }
{ assignment to the resource in the statement }
{$mode objfpc}
{$modeswitch using}
program tusing6;
begin
  using var R := TObject.Create do
    R := TObject.Create;
end.
