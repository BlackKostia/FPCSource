{ {$modeswitch inlinevars} together with the classic var section before
  begin: both kinds of local variables in one routine, nested routines with
  their own var sections, a global var section, consts and types }
{$mode objfpc}{$H+}
{$modeswitch inlinevars}
program tinlinevar22;

uses
  SysUtils;

const
  Limit = 4;

type
  TPoint = record
    X, Y: Integer;
  end;

var
  GlobalCount: Integer;
  GlobalText: string;

procedure Check(Cond: Boolean; Code: Integer);
begin
  if not Cond then
    begin
      WriteLn('failed ', Code);
      Halt(Code);
    end;
end;

function Sum(const A: array of Integer): Integer;
var
  I: Integer;
  Partial: Integer;
begin
  Partial := 0;
  for I := 0 to High(A) do
    Inc(Partial, A[I]);
  { an inline variable after classic ones, using them }
  var Doubled := Partial * 2;
  Result := Doubled div 2;
  Check(I = High(A), 1);
end;

function Describe(N: Integer): string;
var
  P: TPoint;
  Prefix: string;

  { a nested routine with its own var section and inline variables, using
    a classic variable of the outer routine }
  function Coords: string;
  var
    Sep: string;
  begin
    Sep := ',';
    var Text := IntToStr(P.X) + Sep + IntToStr(P.Y);
    Result := Prefix + Text;
  end;

begin
  Prefix := 'p=';
  P.X := N;
  P.Y := N * N;
  var Main := Coords;
  begin
    var Suffix := '!';
    Main := Main + Suffix;
  end;
  { classic variables stay visible after the blocks of inline variables }
  Check(Prefix = 'p=', 2);
  Result := Main;
end;

procedure UseGlobals;
var
  Local: Integer;
begin
  Local := Limit;
  for var I := 1 to Local do
    Inc(GlobalCount, I);
  var Line := GlobalText + IntToStr(GlobalCount);
  GlobalText := Line;
end;

var
  Total: Integer;
begin
  Total := Sum([1, 2, 3, 4]);
  Check(Total = 10, 3);
  Check(Describe(3) = 'p=3,9!', 4);
  GlobalCount := 0;
  GlobalText := 'count=';
  UseGlobals;
  Check(GlobalText = 'count=10', 5);
  { an inline variable in the main block next to the global var section }
  var Extra := Total + GlobalCount;
  Check(Extra = 20, 6);
  WriteLn('ok');
end.
