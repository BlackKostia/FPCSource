{ %FAIL }
{ without the mode switch using is not a statement }
{$mode objfpc}
program tusing5;
begin
  using var L := TObject.Create do
    ;
end.
