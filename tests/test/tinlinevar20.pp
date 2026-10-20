{ %FAIL }
{ a variable of the try part is not visible in the finally part }
{$mode objfpc}
{$modeswitch inlinevars}
program tinlinevar20;
begin
  try
    var X := 1;
  finally
    WriteLn(X);
  end;
end.
