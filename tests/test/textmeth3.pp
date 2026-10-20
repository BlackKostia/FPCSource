{ %FAIL }
{ with typehelpers only (upstream behaviour, unchanged): an own string
  helper hides TStringHelper of SysUtils }
{$mode objfpc}{$H+}
{$modeswitch typehelpers}
program textmeth3;
uses
  SysUtils;
type
  TStrHelper = type helper for string
    function Shout: string;
  end;
function TStrHelper.Shout: string;
begin
  Result := Self + '!';
end;
var
  S: string;
begin
  S := 'a';
  S := S.ToUpper;
end.
