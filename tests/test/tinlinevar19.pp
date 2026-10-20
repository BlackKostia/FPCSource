{ %FAIL }
{ a variable of the body of a repeat loop is not visible after the loop }
{$mode objfpc}
{$modeswitch inlinevars}
program tinlinevar19;
begin
  repeat
    var X := 1;
  until X = 1;
  WriteLn(X);
end.
