{ a declaration with constraints in the interface and an additional overload
  with the same type parameter names in the implementation }
program tgenconstraint54;

{$mode objfpc}{$H+}

uses
  ugenconstraint54;

var
  o: TObject;
begin
  o := TObject.Create;
  if PickViaOverload(o, 1) <> o then
    Halt(1);
  if PickViaOverload(o, 0) <> nil then
    Halt(2);
  if specialize MakeBox<TObject>(o).Obj <> o then
    Halt(3);
  o.Free;
  Writeln('ok');
end.
