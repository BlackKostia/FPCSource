{ %OPT=-gh }
{ {$modeswitch using}: a variable of a var section as resource (it is nil
  after the statement), COM interfaces (released at the end of the
  statement), generic routines, together with inlinevars }
{$mode objfpc}{$H+}
{$modeswitch using}
{$modeswitch inlinevars}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
program tusing2;

uses
  SysUtils, Classes;

type
  TRes = class
  public
    Name: string;
    constructor Create(const AName: string);
    destructor Destroy; override;
  end;

  IRes = interface
    ['{4F1D2B6A-3C2E-4E7B-9D61-2A7C5B0E9F11}']
    function GetName: string;
  end;

  TIntfRes = class(TInterfacedObject, IRes)
  public
    FName: string;
    constructor Create(const AName: string);
    destructor Destroy; override;
    function GetName: string;
  end;

  { a class with its own Free: the using statement calls TObject.Free }
  TOwnFree = class(TRes)
  public
    procedure Free(Code: Integer);
  end;

  TCounter = reference to function: Integer;

  generic TBox<T: TRes> = class
  public
    function Use(const AName: string): string;
  end;

var
  Log: string;
  Alive: Integer;

constructor TRes.Create(const AName: string);
begin
  Name := AName;
  Inc(Alive);
  Log := Log + '+' + Name;
end;

destructor TRes.Destroy;
begin
  Dec(Alive);
  Log := Log + '-' + Name;
  inherited Destroy;
end;

constructor TIntfRes.Create(const AName: string);
begin
  FName := AName;
  Inc(Alive);
  Log := Log + '+' + FName;
end;

destructor TIntfRes.Destroy;
begin
  Dec(Alive);
  Log := Log + '-' + FName;
  inherited Destroy;
end;

function TIntfRes.GetName: string;
begin
  Result := FName;
end;

procedure TOwnFree.Free(Code: Integer);
begin
  Log := Log + 'own' + IntToStr(Code);
end;

procedure Check(Cond: Boolean; Code: Integer);
begin
  if not Cond then
    begin
      WriteLn('failed ', Code, ' log=', Log, ' alive=', Alive);
      Halt(Code);
    end;
end;

procedure Expect(const Expected: string; Code: Integer);
begin
  Check(Log = Expected, Code);
  Check(Alive = 0, Code + 100);
  Log := '';
end;

{ a variable of the var section: freed and set to nil }
procedure VarSection;
var
  R: TRes;
  L: TStringList;
begin
  using R := TRes.Create('v') do
    Log := Log + R.Name;
  Check(R = nil, 1);
  Expect('+vv-v', 2);
  { reused for the next resource }
  using R := TRes.Create('w') do
    Log := Log + '.';
  Check(R = nil, 3);
  Expect('+w.-w', 4);
  using L := TStringList.Create do
    begin
      L.Add('one');
      L.Add('two');
      Check(L.Count = 2, 5);
    end;
  Check(L = nil, 6);
end;

{ a parameter and a global variable as resource }
var
  GlobalRes: TRes;

procedure ParamRes(R: TRes);
begin
  using R := TRes.Create('par') do
    Log := Log + '.';
  Check(R = nil, 7);
end;

procedure GlobalAndParam;
begin
  using GlobalRes := TRes.Create('g') do
    Log := Log + '.';
  Check(GlobalRes = nil, 8);
  Expect('+g.-g', 9);
  ParamRes(nil);
  Expect('+par.-par', 10);
end;

{ the var section variable is nil also after an exception }
procedure VarSectionException;
var
  R: TRes;
begin
  R := nil;
  try
    using R := TRes.Create('e') do
      raise Exception.Create('x');
  except
    on Exception do
      Log := Log + '!';
  end;
  Check(R = nil, 11);
  Expect('+e-e!', 12);
end;

{ mixed: an inline resource and a var section resource }
procedure Mixed;
var
  B: TRes;
begin
  using var A := TRes.Create('a'), B := TRes.Create('b') do
    Log := Log + '.';
  Check(B = nil, 13);
  Expect('+a+b.-b-a', 14);
end;

{ a COM interface is released at the end of the statement, not at the end
  of the routine }
procedure Interfaces;
var
  I: IRes;
begin
  using var R := IRes(TIntfRes.Create('i')) do
    Log := Log + R.GetName;
  Expect('+ii-i', 15);
  using var R: IRes := TIntfRes.Create('j') do
    begin
      { another reference keeps the object alive }
      I := R;
      Log := Log + '.';
    end;
  Check(Log = '+j.', 16);
  Check(I.GetName = 'j', 17);
  I := nil;
  Expect('+j.-j', 18);
  using I := TIntfRes.Create('k') do
    Log := Log + '.';
  Check(I = nil, 19);
  Expect('+k.-k', 20);
end;

procedure OwnFree;
begin
  using var R := TOwnFree.Create('o') do
    R.Free(1);
  Expect('+oown1-o', 21);
end;

{ in a generic routine and a method of a generic class }
generic function MakeAndFree<T: TRes>(const AName: string): string;
begin
  using var R := T.Create(AName) do
    Result := R.Name;
end;

function TBox.Use(const AName: string): string;
begin
  using var R := T.Create(AName) do
    Result := R.Name + R.ClassName;
end;

procedure Generics;
begin
  Check(specialize MakeAndFree<TRes>('gen') = 'gen', 22);
  Expect('+gen-gen', 23);
  using var Box := specialize TBox<TRes>.Create do
    Check(Box.Use('x') = 'xTRes', 24);
  Expect('+x-x', 27);
end;

{ together with inline variables }
procedure WithInlineVars;
begin
  var Total := 0;
  for var I := 1 to 3 do
    using var R := TRes.Create(IntToStr(I)) do
      begin
        var Len := Length(R.Name);
        Total := Total + Len;
      end;
  Check(Total = 3, 25);
  Expect('+1-1+2-2+3-3', 26);
end;

{ an anonymous function captures the resources }
procedure Captured;
var
  V: TStringList;
  F: TCounter;
begin
  using var L := TStringList.Create, V := TStringList.Create do
    begin
      L.Add('a');
      V.Add('b');
      V.Add('c');
      F := function: Integer
        begin
          Result := L.Count * 10 + V.Count;
        end;
      Check(F() = 12, 28);
    end;
  Check(V = nil, 29);
end;

begin
  VarSection;
  GlobalAndParam;
  VarSectionException;
  Mixed;
  Interfaces;
  OwnFree;
  Generics;
  WithInlineVars;
  Captured;
  WriteLn('ok');
end.
