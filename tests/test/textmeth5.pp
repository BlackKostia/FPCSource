{ %FAIL }
{ extensionmethods- also switches typehelpers off }
{$mode objfpc}{$H+}
{$modeswitch extensionmethods}
{$modeswitch extensionmethods-}
program textmeth5;
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
