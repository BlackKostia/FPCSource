{ %FAIL }
{ the loop variable of "for var" cannot be assigned in the loop }
{$mode objfpc}
{$modeswitch inlinevars}
program tinlinevar17;
begin
  for var I := 1 to 3 do
    I := 5;
end.
