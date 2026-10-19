{ the same routines used through implicit function specialization }
program tgenconstraint42;

{$mode objfpc}{$H+}
{$modeswitch implicitfunctionspecialization}

uses
  ugenconstraint41;

type
  TTest = class
    Value: LongInt;
  end;

var
  t: TTest;
  b: specialize TBox<TTest>;
begin
  t := TTest.Create;
  t.Value := 7;
  b := MakeBox(t);
  if b.Obj <> t then
    Halt(1);
  { inferring T from a "specialize TBox<T>" parameter of a routine from
    another unit is not supported (and raised internal error 2021020905
    after a preceding implicit specialization even without constraints),
    so specialize explicitly here }
  if specialize Unbox<TTest>(b).Value <> 7 then
    Halt(2);
  t.Free;
  Writeln('ok');
end.
