{ %FAIL }
{ a resource of a record type }
{$mode objfpc}
{$modeswitch using}
program tusing11;
type
  TRec = record
    X: Integer;
  end;
var
  Rec: TRec;
begin
  using var R := Rec do
    ;
end.
