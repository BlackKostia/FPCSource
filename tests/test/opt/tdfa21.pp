{ %OPT=-Oodfa -Sew -vw }
{ %norun }
{ the finalization of a unit reads variables of the unit that are assigned
  elsewhere in the unit or whose address is taken: no warning (unlike tdfa8,
  where the variable is assigned nowhere) }
unit tdfa21;

interface

procedure SetI;

implementation

var
  i, k : longint;
  p : ^longint;

procedure SetI;
begin
  i:=1;
end;

initialization
  p:=@k;
finalization
  writeln(i, ' ', k, ' ', p<>nil);
end.
