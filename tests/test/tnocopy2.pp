{ nocopy generic records, specializations and types from another unit }
program tnocopy2;

{$mode objfpc}{$H+}
{$modeswitch implicitfunctionspecialization}

uses
  unocopy2;

procedure Use(constref aBox: specialize TBox<LongInt>; const aPlain: TPlain);
begin
  if (aBox.Value <> 4) or (aPlain.Value <> 0) then
    Halt(1);
end;

var
  a, b: specialize TBox<LongInt>;
  p: TPlain;
begin
  a := MakeBox(LongInt(4));
  b := a.Move;
  if (b.Value <> 4) or (a.Value <> 0) then
    Halt(2);
  p := Default(TPlain);
  Use(b, p);
  Writeln('ok');
end.
