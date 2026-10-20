{ %FAIL }
{ without $modeswitch inlinevars, inline variables are not allowed (as in
  FPC) }
{$mode objfpc}
program tinlinevar6;
begin
  var X := 1;
  WriteLn(X);
end.
