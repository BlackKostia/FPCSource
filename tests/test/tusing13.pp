{ %FAIL }
{ a field is not a resource variable }
{$mode objfpc}
{$modeswitch using}
program tusing13;
type
  THolder = class
    F: TObject;
  end;
var
  H: THolder;
begin
  H := THolder.Create;
  using H.F := TObject.Create do
    ;
end.
