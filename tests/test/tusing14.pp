{ %FAIL }
{ the type of the resource cannot be inferred from nil }
{$mode objfpc}
{$modeswitch using}
program tusing14;
begin
  using var R := nil do
    ;
end.
