{ %FAIL }
{ the loop variable of "for var" is not visible after the loop }
{$mode objfpc}
{$modeswitch inlinevars}
program tinlinevar8;
begin
  for var I := 1 to 3 do
    WriteLn(I);
  WriteLn(I);
end.
