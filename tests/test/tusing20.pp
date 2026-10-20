{ %FAIL }
{ a function call is not a resource variable }
{$mode objfpc}
{$modeswitch using}
program tusing20;
function F: TObject;
begin
  Result := nil;
end;
begin
  using F := TObject.Create do
    ;
end.
