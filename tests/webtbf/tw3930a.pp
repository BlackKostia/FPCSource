{ %fail }
{ %KNOWNCOMPILEERROR=type TStringList is not a distinct type for assignment compatibility; making it strict would break existing code, not pursued }

{ Gives under Kylix:

tw3930a.pp(22) Error: Incompatible types: 'TMyStringList' and 'TStringList'

}

{$ifdef fpc}
{$mode objfpc}
{$endif}
uses
  Classes;

type
  TMyStringList = type TStringlist;

var
  list : TMyStringList;

begin
  list:=TMyStringList.Create;
end.


