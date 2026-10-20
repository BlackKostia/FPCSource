{ %FAIL }
{ an inline variable is not visible after its block }
{$mode objfpc}
{$modeswitch inlinevars}
program tinlinevar7;
begin
  begin
    var X := 1;
  end;
  WriteLn(X);
end.
