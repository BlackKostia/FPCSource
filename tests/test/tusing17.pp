{ %FAIL }
{ a class reference is not a resource }
{$mode objfpc}
{$modeswitch using}
program tusing17;
begin
  using var C := TObject do
    ;
end.
