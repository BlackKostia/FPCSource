{ %OPT=-gh -gw -O3 }
{ {$modeswitch interpolation} in mode delphi: generics (replayed tokens), a
  unit, an inline routine, together with inlinevars }
{$mode delphi}{$H+}
{$modeswitch interpolation}
{$modeswitch inlinevars}
program tinterp2;

uses
  uinterp2;

procedure Check(const Got, Expected: string; Code: Integer);
begin
  if Got <> Expected then
    begin
      WriteLn('failed ', Code, ': got "', Got, '" expected "', Expected, '"');
      Halt(Code);
    end;
end;

begin
  Check(InitText, 'unit (1, 2)', 1);
  Check(Tagged<Integer>('int', 42), '[int] 42', 2);
  Check(Tagged<string>('str', 'abc'), '[str] abc', 3);
  Check(Tagged<Boolean>('bool', False), '[bool] FALSE', 4);
  var IntBox := TBox<Integer>.Create;
  IntBox.Value := 7;
  Check(IntBox.Show('i'), 'i=<7>', 5);
  IntBox.Free;
  var StrBox := TBox<string>.Create;
  StrBox.Value := 'seven';
  Check(StrBox.Show('s'), 's=<seven>', 6);
  StrBox.Free;
  Check(Pair(3, 4), '(3, 4)', 7);
  { the type of an inline variable initialized with an interpolated string }
  var S := $'{Pair(5, 6)}!';
  S := S + '?';
  Check(S, '(5, 6)!?', 8);
  WriteLn('ok');
end.
