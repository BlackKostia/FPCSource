{ %FAIL }
{ a declaration is a statement of a statement list, not the single
  statement of an if }
{$mode objfpc}
{$modeswitch inlinevars}
program tinlinevar9;
begin
  if ParamCount > 0 then
    var X := 1;
end.
