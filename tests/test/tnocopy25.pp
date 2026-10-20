{ %FAIL }
{ TScoped<T> of smartptrs is declared "nocopy" }
program tnocopy25;

{$mode objfpc}

uses
  classes, smartptrs;

var
  a, b: specialize TScoped<TStringList>;
begin
  a.Reset(TStringList.Create);
  b := a;
end.
