{ %FAIL }
{ with the mode switch using is a reserved word }
{$mode objfpc}
{$modeswitch using}
program tusing15;
var
  using: Integer;
begin
  using := 1;
end.
