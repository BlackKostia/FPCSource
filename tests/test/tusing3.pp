{ without {$modeswitch using} "using" is an ordinary identifier }
{$mode objfpc}
program tusing3;

type
  TUsing = record
    using: Integer;
  end;

var
  using: Integer;
  R: TUsing;

procedure Use(using: Integer);
begin
  if using <> 3 then
    Halt(1);
end;

begin
  using := 3;
  Use(using);
  R.using := using;
  if R.using <> 3 then
    Halt(2);
  WriteLn('ok');
end.
