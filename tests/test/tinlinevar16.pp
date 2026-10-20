{ %FAIL }
{ the initialization cannot use the variable it initializes }
{$mode objfpc}
{$modeswitch inlinevars}
program tinlinevar16;
begin
  var X := X + 1;
end.
