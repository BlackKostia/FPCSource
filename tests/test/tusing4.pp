{ %OPT=-gh -gw -O3 }
{ {$modeswitch using} in mode delphi, in a unit, with debug information and
  optimizations }
{$mode delphi}{$H+}
{$modeswitch using}
program tusing4;

uses
  Classes, uusing4;

procedure Check(Cond: Boolean; Code: Integer);
begin
  if not Cond then
    begin
      WriteLn('failed ', Code);
      Halt(Code);
    end;
end;

var
  S: TStringList;

begin
  Check(InitCount = 1, 1);
  Check(JoinLines('a', 'b') = 'a,b,', 2);
  Check(CountLines('a'#10'b'#10'c') = 3, 3);
  Check(MakeAndName<TStringList> = 'TStringList1', 4);
  using S := TStringList.Create do
    S.Add('main');
  Check(S = nil, 5);
  WriteLn('ok');
end.
