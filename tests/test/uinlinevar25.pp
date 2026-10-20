{ unit of tinlinevar25: inline variables of the initialization captured by
  anonymous functions }
{$mode objfpc}{$H+}
{$modeswitch inlinevars}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
unit uinlinevar25;

interface

type
  TStrFunc = reference to function: string;

var
  InitFunc: TStrFunc;
  InitValue: string;

implementation

initialization
  var Prefix := 'init';
  var N := 25;
  InitFunc := function: string
    begin
      Result := Prefix + '-' + Chr(Ord('0') + N div 10) + Chr(Ord('0') + N mod 10);
    end;
  InitValue := InitFunc();
end.
