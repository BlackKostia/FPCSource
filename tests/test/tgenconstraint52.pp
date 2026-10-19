{ constrained generic functions with constrained generic result types in
  mode Delphi, including the class+constructor constraint }
program tgenconstraint52;

{$mode delphi}{$H+}

uses
  ugenconstraint52;

type
  TTest = class
    Value: LongInt;
    constructor Create;
  end;

constructor TTest.Create;
begin
  Value := 11;
end;

var
  t: TTest;
  b: TBox<TTest>;
  n: TCtorBox<TTest>;
begin
  t := TTest.Create;
  b := MakeBox<TTest>(t);
  if b.Obj <> t then
    Halt(1);
  b := TBoxes.Make<TTest>(t);
  if b.Obj <> t then
    Halt(2);
  n := NewBox<TTest>;
  if not Assigned(n.Obj) or (n.Obj.Value <> 11) then
    Halt(3);
  n.Obj.Free;
  t.Free;
  Writeln('ok');
end.
