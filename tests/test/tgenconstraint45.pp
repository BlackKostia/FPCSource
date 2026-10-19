{ mixed constrained/unconstrained type parameters and overloads }
program tgenconstraint45;

{$mode objfpc}{$H+}

uses
  ugenconstraint45;

var
  o: TObject;
  pi: specialize TPair<TObject, LongInt>;
  ps: specialize TPair<TObject, String>;
begin
  o := TObject.Create;
  pi := specialize MakePair<TObject, LongInt>(o, 5);
  if (pi.Key <> o) or (pi.Value <> 5) then
    Halt(1);
  ps := specialize SwapPair<String, TObject>('abc', o);
  if (ps.Key <> o) or (ps.Value <> 'abc') then
    Halt(2);
  if specialize Count<TObject>(pi) <> 5 then
    Halt(3);
  if specialize Count<TObject>(ps) <> 3 then
    Halt(4);
  o.Free;
  Writeln('ok');
end.
