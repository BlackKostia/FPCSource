{ %OPT=-gh }
{ inline variables of the main program and of the initialization of a unit
  (their "local" symtable is the static symtable) captured by anonymous
  functions; the same name in sibling blocks of the main program }
{$mode objfpc}{$H+}
{$modeswitch inlinevars}
{$modeswitch tuples}
{$modeswitch using}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
program tinlinevar25;

uses
  Classes, uinlinevar25;

type
  TIntFunc = reference to function: Integer;
  TStrFunc2 = reference to function: string;

var
  F: TIntFunc;
  G: TStrFunc2;

procedure Check(Cond: Boolean; Code: Integer);
begin
  if not Cond then
    begin
      WriteLn('failed ', Code);
      Halt(Code);
    end;
end;

begin
  Check(InitValue = 'init-25', 1);
  Check(InitFunc() = 'init-25', 2);

  var X := 41;
  F := function: Integer begin Result := X + 1; end;
  Check(F() = 42, 3);
  { the anonymous function sees later changes and can change the variable }
  X := 99;
  Check(F() = 100, 4);
  G := function: string begin X := 7; Result := 'set'; end;
  Check(G() = 'set', 5);
  Check(X = 7, 6);

  { managed types }
  var S := 'abc';
  G := function: string begin Result := S + S; end;
  Check(G() = 'abcabc', 7);

  { the same name in sibling blocks, with another type }
  begin
    var Y := 10;
    F := function: Integer begin Result := Y * 2; end;
    Check(F() = 20, 8);
  end;
  begin
    var Y := 'second';
    G := function: string begin Result := Y + '!'; end;
    Check(G() = 'second!', 9);
  end;

  { loops }
  var Sum := 0;
  for var I := 1 to 3 do
    begin
      F := function: Integer begin Result := I * 10; end;
      Sum := Sum + F();
    end;
  Check(Sum = 60, 10);
  for var Item in ['a', 'b'] do
    begin
      var Line: string;
      Line := Line + Item;
      G := function: string begin Result := Line; end;
      Check(G() = Item, 11);
    end;

  { tuples }
  var (Q, R) := (17 div 5, 17 mod 5);
  F := function: Integer begin Result := Q * 10 + R; end;
  Check(F() = 32, 12);

  { a using resource }
  using var L := TStringList.Create do
    begin
      L.Add('x');
      L.Add('y');
      F := function: Integer begin Result := L.Count; end;
      Check(F() = 2, 13);
    end;

  F := nil;
  G := nil;
  InitFunc := nil;
  WriteLn('ok');
end.
