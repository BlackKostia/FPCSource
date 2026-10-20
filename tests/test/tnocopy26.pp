{ %FAIL }
{ the lock guards of syncobjs are declared "nocopy" }
program tnocopy26;

{$mode objfpc}

uses
  {$ifdef unix}cthreads,{$endif}
  syncobjs;

var
  cs: TCriticalSection;
  g1, g2: TCriticalSectionGuard;
begin
  cs := TCriticalSection.Create;
  g1.Init(cs);
  g2 := g1;
end.
