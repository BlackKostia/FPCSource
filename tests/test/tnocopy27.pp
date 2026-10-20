{ allowed operations with the nocopy TScoped<T> and the copyable TArc<T> }
program tnocopy27;

{$mode objfpc}
{$modeswitch implicitfunctionspecialization}

uses
  classes, smartptrs;

type
  TListScoped = specialize TScoped<TStringList>;
  TListArc = specialize TArc<TStringList>;

function Count(const aList: TListScoped): Integer;
begin
  Result := aList.Obj.Count;
end;

var
  a, b: TListScoped;
  x, y: TListArc;
begin
  a := MakeScoped(TStringList.Create);
  a.Obj.Add('x');
  b := a.Move;
  if a.IsAssigned or (Count(b) <> 1) then
    Halt(1);
  x := MakeArc(TStringList.Create);
  y := x;
  if x.UseCount <> 2 then
    Halt(2);
  Writeln('ok');
end.
