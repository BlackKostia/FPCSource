{ constrained global generic functions declared in a unit interface with a
  specialization of a constrained generic in their result/parameter types }
program tgenconstraint41;

{$mode objfpc}{$H+}

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
  t.Value := 42;
  b := specialize MakeBox<TTest>(t);
  if b.Obj <> t then
    Halt(1);
  if specialize Unbox<TTest>(b).Value <> 42 then
    Halt(2);
  b.Obj := nil;
  specialize FillBox<TTest>(b, t);
  if b.Obj <> t then
    Halt(3);
  t.Free;
  Writeln('ok');
end.
