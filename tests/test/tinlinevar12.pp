{ %FAIL }
{ an initialization only for a single variable }
{$mode objfpc}
{$modeswitch inlinevars}
program tinlinevar12;
begin
  var A, B: Integer := 0;
end.
