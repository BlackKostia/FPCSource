{ %FAIL }
{ the type is inferred once, it stays static }
{$mode objfpc}{$H+}
{$modeswitch inlinevars}
program tinlinevar15;
begin
  var X := 5;
  X := 'text';
end.
