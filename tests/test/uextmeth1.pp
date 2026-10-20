{ unit of textmeth1: helpers declared in a unit }
{$mode objfpc}{$H+}
{$modeswitch extensionmethods}
unit uextmeth1;

interface

type
  TStrUnitHelper = type helper for string
    function Words: Integer;
  end;

  TIntUnitHelper = type helper for Integer
    function Who: string;
  end;

implementation

function TStrUnitHelper.Words: Integer;
var
  I: Integer;
  InWord: Boolean;
begin
  Result := 0;
  InWord := False;
  for I := 1 to Length(Self) do
    if Self[I] = ' ' then
      InWord := False
    else if not InWord then
      begin
        InWord := True;
        Inc(Result);
      end;
end;

function TIntUnitHelper.Who: string;
begin
  Result := 'unit';
end;

end.
