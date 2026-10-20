{ implicit specialization of generic routines from a unit that is compiled
  in the same compiler run; their parameter types are specializations
  (previously the definitions were freed after compiling the unit: wrong
  "Wrong number of parameters" or internal error 2021020905) }
program tgenfunc28;

{$mode objfpc}{$H+}
{$modeswitch implicitfunctionspecialization}

uses
  ugenfunc28;

type
  TTest = class
  end;

var
  b: specialize TBox<LongInt>;
  cb: specialize TClassBox<TTest>;
  t: TTest;
  v: LongInt;
begin
  b.Obj := 42;
  if Unbox(b) <> 42 then
    Halt(1);
  v := 7;
  b := MakeBox(v);
  if Unbox(b) <> 7 then
    Halt(2);
  t := TTest.Create;
  cb := MakeClassBox(t);
  if UnboxClass(cb) <> t then
    Halt(3);
  t.Free;
  Writeln('ok');
end.
