{ Implicit operators between a generic record and its class-constrained
  type parameter in mode Delphi }
program tgenconstraint57;

{$mode delphi}{$H+}

type
  TBox<T: class> = record
    Obj: T;
    class operator Implicit(const aBox: TBox<T>): T;
    class operator Implicit(aObj: T): TBox<T>;
  end;

class operator TBox<T>.Implicit(const aBox: TBox<T>): T;
begin
  Result := aBox.Obj;
end;

class operator TBox<T>.Implicit(aObj: T): TBox<T>;
begin
  Result.Obj := aObj;
end;

var
  b: TBox<TObject>;
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
