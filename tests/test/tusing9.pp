{ %FAIL }
{ the inline resource is not visible after the statement }
{$mode objfpc}
{$modeswitch using}
program tusing9;
begin
  using var R := TObject.Create do
    ;
  R.Free;
end.
