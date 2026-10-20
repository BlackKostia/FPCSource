{ %FAIL }
{ an inline variable cannot redeclare a variable of the var section of the
  same routine }
{$mode objfpc}
{$modeswitch inlinevars}
program tinlinevar23;

procedure P;
var
  Count: Integer;
begin
  Count := 1;
  var Count := 2;
end;

begin
  P;
end.
