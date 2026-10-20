{ %FAIL }
{ an assignment to the resource in a later resource of the same statement }
{$mode objfpc}
{$modeswitch using}
program tusing18;
var
  A: TObject;
begin
  using A := TObject.Create, A := TObject.Create do
    ;
end.
