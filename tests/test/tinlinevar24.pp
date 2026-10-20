{ %FAIL }
{ an inline variable of a nested block cannot redeclare a variable of the
  var section of the routine either }
{$mode objfpc}
{$modeswitch inlinevars}
program tinlinevar24;

procedure P;
var
  Count: Integer;
begin
  Count := 1;
  begin
    var Count := 'nested';
  end;
end;

begin
  P;
end.
