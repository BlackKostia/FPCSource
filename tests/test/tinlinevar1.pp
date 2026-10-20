{ {$modeswitch inlinevars}: declarations, inferred types, block scope }
{$mode objfpc}{$H+}
{$modeswitch inlinevars}
program tinlinevar1;

uses
  Classes;

type
  TColor = (Red, Green, Blue);

var
  Shadow: Integer;

procedure Check(Cond: Boolean; Code: Integer);
begin
  if not Cond then
    begin
      WriteLn('failed ', Code);
      Halt(Code);
    end;
end;

function Twice(X: Integer): Integer;
begin
  Result := X * 2;
end;

procedure Scopes;
begin
  begin
    var Y := 1;
    Check(Y = 1, 40);
  end;
  { the same name in the next block, with another type }
  begin
    var Y := 'second';
    Check(Y = 'second', 41);
  end;
  { an inline variable hides a global one in its block only }
  Shadow := 7;
  begin
    var Shadow := 'local';
    Check(Shadow = 'local', 42);
  end;
  Check(Shadow = 7, 43);
  { the initialization does not see the variable it initializes }
  begin
    var Shadow := Shadow + 1;
    Check(Shadow = 8, 44);
  end;
  Check(Shadow = 7, 45);
end;

begin
  { inferred types: integer constants are Integer or Int64, string
    constants a string, others the type of the expression }
  var I := 5;
  Check(SizeOf(I) = SizeOf(Integer), 1);
  var Big := 10000000000;
  Check((SizeOf(Big) = 8) and (Big = 10000000000), 2);
  var Neg := -3;
  Check((SizeOf(Neg) = SizeOf(Integer)) and (Neg = -3), 3);
  var S := 'text';
  S := S + ' more';
  Check(S = 'text more', 4);
  var F := 2.5;
  Check(F = 2.5, 5);
  var B := I > 3;
  Check(B, 6);
  var C := Green;
  Check(C = Green, 7);
  var T := Twice(21);
  Check(T = 42, 8);
  var L := TStringList.Create;
  L.Add(S);
  Check(L.Count = 1, 9);
  L.Free;
  { explicit types, with and without an initialization }
  var W: Word := 65535;
  Check(W = 65535, 10);
  var X, Z: Integer;
  X := 1;
  Z := 2;
  Check(X + Z = 3, 11);
  var O: TObject := nil;
  Check(O = nil, 12);
  var P: Pointer;
  P := @I;
  Check(PInteger(P)^ = 5, 13);
  Scopes;
  WriteLn('ok');
end.
