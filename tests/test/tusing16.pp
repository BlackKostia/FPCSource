{ %FAIL }
{ an initialization is required }
{$mode objfpc}
{$modeswitch using}
program tusing16;
begin
  using var R: TObject do
    ;
end.
