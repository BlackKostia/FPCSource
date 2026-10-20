{ {$modeswitch extensionmethods} in mode delphi: record helpers for
  standard types together with the helpers of SysUtils }
{$mode delphi}{$H+}
{$modeswitch extensionmethods}
program textmeth2;

uses
  SysUtils;

type
  TStrHelper = record helper for string
    function Shout: string;
  end;

  TIntHelper = record helper for Integer
    function IsEven: Boolean;
  end;

function TStrHelper.Shout: string;
begin
  Result := UpperCase(Self) + '!';
end;

function TIntHelper.IsEven: Boolean;
begin
  Result := not Odd(Self);
end;

var
  S: string;
  I: Integer;

begin
  S := 'abc';
  I := 4;
  if S.Shout <> 'ABC!' then
    Halt(1);
  if S.ToUpper <> 'ABC' then
    Halt(2);
  if not I.IsEven or (I.ToString <> '4') then
    Halt(3);
  WriteLn('ok');
end.
