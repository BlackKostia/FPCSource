{ constrained generic methods of records and classes declared in a unit
  interface with a specialization of a constrained generic in their
  result/parameter types }
program tgenconstraint43;

{$mode objfpc}{$H+}

uses
  ugenconstraint43;

type
  TTest = class
  end;

var
  t: TTest;
  b: specialize TBox<TTest>;
  r: TBoxes;
  f: TBoxFactory;
begin
  t := TTest.Create;
  b := TBoxes.specialize Make<TTest>(t);
  if b.Obj <> t then
    Halt(1);
  if r.specialize Get<TTest>(b) <> t then
    Halt(2);
  f := TBoxFactory.Create;
  b.Obj := nil;
  b := f.specialize Make<TTest>(t);
  if b.Obj <> t then
    Halt(3);
  b.Obj := nil;
  b := TBoxFactory.specialize MakeStatic<TTest>(t);
  if b.Obj <> t then
    Halt(4);
  f.Free;
  t.Free;
  Writeln('ok');
end.
