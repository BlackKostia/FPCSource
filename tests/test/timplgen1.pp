{ the extended generic type inference of {$modeswitch implicitgenerics}
  infers T through a procedural type with a constant generic parameter,
  which plain implicitfunctionspecialization rejects like upstream FPC
  (see timpfuncspez15) }
{$mode objfpc}
{$modeswitch implicitgenerics}
program timplgen1;

type
  generic TProc<T; const U: integer> = procedure(value: T = U);

var
  Got: integer;

generic procedure Run<T>(proc: specialize TProc<T, 10>);
begin
  proc();
end;

procedure DoCallback(value: integer);
begin
  Got := value;
end;

begin
  Got := 0;
  Run(@DoCallback);
  if Got <> 10 then
    halt(1);
  writeln('ok');
end.
