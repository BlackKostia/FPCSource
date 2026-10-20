{ %FAIL }
{ an inline variable cannot redeclare a parameter }
{$mode objfpc}
{$modeswitch inlinevars}
program tinlinevar14;

procedure P(A: Integer);
begin
  var A := 2;
end;

begin
  P(1);
end.
