{ %FAIL }
{ the resource passed as var parameter in the statement }
{$mode objfpc}
{$modeswitch using}
program tusing8;

procedure Replace(var Obj: TObject);
begin
  Obj := nil;
end;

begin
  using var R := TObject.Create do
    Replace(R);
end.
