{ %OPT=-gw -O3 }
{ inline variables in a unit: in a generic routine specialized here, in an
  inline routine, in the initialization of the unit; with debug
  information and optimizations }
{$mode objfpc}{$H+}
{$modeswitch inlinevars}
program tinlinevar21;

uses
  uinlinevar21;

procedure Check(Cond: Boolean; Code: Integer);
begin
  if not Cond then
    begin
      WriteLn('failed ', Code);
      Halt(Code);
    end;
end;

begin
  Check(InitValue = 'initialized', 1);
  Check(specialize JoinTwice<Integer>(12) = '1212', 2);
  Check(specialize JoinTwice<string>('ab') = 'abab', 3);
  var N := Square(7);
  Check(N = 49, 4);
  WriteLn('ok');
end.
