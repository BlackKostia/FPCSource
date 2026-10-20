{ %FAIL }
{ the type of an array constructor cannot be inferred }
{$mode objfpc}
{$modeswitch inlinevars}
program tinlinevar18;
begin
  var A := [1, 2, 3];
end.
