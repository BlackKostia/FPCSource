{ %FAIL }
{ the same name twice in one block }
{$mode objfpc}
{$modeswitch inlinevars}
program tinlinevar13;
begin
  var X := 1;
  var X := 2;
end.
