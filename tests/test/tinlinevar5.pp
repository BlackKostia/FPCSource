{ {$modeswitch inlinevars} with {$modeswitch tuples}: the variables of
  "var (A, B) := ..." are visible to the end of the statement list, like
  the other inline variables, so the names can be used again }
{$mode objfpc}{$H+}
{$modeswitch tuples}
{$modeswitch inlinevars}
program tinlinevar5;

function DivRem(A, B: Integer): (Integer, Integer);
begin
  Result := (Integer(A div B), Integer(A mod B));
end;

procedure Check(Cond: Boolean; Code: Integer);
begin
  if not Cond then
    begin
      WriteLn('failed ', Code);
      Halt(Code);
    end;
end;

begin
  begin
    var (Q, R) := DivRem(17, 5);
    Check((Q = 3) and (R = 2), 1);
  end;
  begin
    var (Q, R) := DivRem(9, 4);
    Check((Q = 2) and (R = 1), 2);
  end;
  for var I := 1 to 2 do
    begin
      var (Q, R) := DivRem(I * 10, 3);
      Check(Q * 3 + R = I * 10, 3);
    end;
  WriteLn('ok');
end.
