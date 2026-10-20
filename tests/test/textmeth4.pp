{ %FAIL }
{ without a mode switch a type helper for Integer is not allowed in mode objfpc }
{$mode objfpc}{$H+}
program textmeth4;
type
  TIntHelper = type helper for Integer
    function IsEven: Boolean;
  end;
function TIntHelper.IsEven: Boolean;
begin
  Result := not Odd(Self);
end;
begin
end.
