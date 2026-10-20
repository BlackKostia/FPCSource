{ %FAIL }
{ a CORBA interface is not reference counted }
{$mode objfpc}
{$modeswitch using}
{$interfaces corba}
program tusing12;
type
  ICorba = interface
    procedure P;
  end;
var
  I: ICorba;
begin
  using I := nil do
    ;
end.
