{ %OPT=-Oodfa -Sew -vw }
{ %KNOWNCOMPILEERROR=The dfa does not relate the equal conditions of the assignment and the use (path sensitive dfa is not implemented) }
{ %norun }

{ this test test needs dynamic dfa to work properly,
  this is a reminder so it will not be forgotten }
var
  j,i : longint;

begin
  j:=paramcount;
  if j=1 then
    i:=1;
  writeln;
  if j=1 then
    writeln(i);
end.
