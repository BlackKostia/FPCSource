{ assignment operators between a generic record and its class-constrained
  type parameter in mode objfpc }
program tgenconstraint56;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

type
  generic TBox<T: class> = record
    Obj: T;
    class operator :=(constref aBox: TBox): T;
    class operator :=(aObj: T): TBox;
  end;

class operator TBox.:=(constref aBox: TBox): T;
begin
  Result := aBox.Obj;
end;

class operator TBox.:=(aObj: T): TBox;
begin
  Result.Obj := aObj;
end;

var
  b: specialize TBox<TObject>;
  o, r: TObject;
begin
  o := TObject.Create;
  b := o;
  if b.Obj <> o then
    Halt(1);
  r := b;
  if r <> o then
    Halt(2);
  o.Free;
  Writeln('ok');
end.
