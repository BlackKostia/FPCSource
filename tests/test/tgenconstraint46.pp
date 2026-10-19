{ forward declaration inside a program: here the constraints have to be
  repeated in the implementation }
program tgenconstraint46;

{$mode objfpc}{$H+}

type
  generic TBox<T: class> = record
    Obj: T;
  end;

generic function MakeBox<T: class>(aObj: T): specialize TBox<T>; forward;

procedure Test;
var
  o: TObject;
begin
  o := TObject.Create;
  if specialize MakeBox<TObject>(o).Obj <> o then
    Halt(1);
  o.Free;
end;

generic function MakeBox<T: class>(aObj: T): specialize TBox<T>;
begin
  Result.Obj := aObj;
end;

begin
  Test;
  Writeln('ok');
end.
