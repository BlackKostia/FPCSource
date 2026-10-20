{ %OPT=-gh }
{ {$modeswitch inlinevars}: inline variables of managed types are finalized
  with the other locals (also after exceptions and Exit), and a variable
  declared without initialization in a loop starts empty at each iteration }
{$mode objfpc}{$H+}
{$modeswitch inlinevars}
program tinlinevar3;

uses
  SysUtils;

type
  ICounted = interface
    function Value: Integer;
  end;

  TCounted = class(TInterfacedObject, ICounted)
    FValue: Integer;
    constructor Create(AValue: Integer);
    destructor Destroy; override;
    function Value: Integer;
  end;

var
  Alive: Integer;

constructor TCounted.Create(AValue: Integer);
begin
  inherited Create;
  FValue := AValue;
  Inc(Alive);
end;

destructor TCounted.Destroy;
begin
  Dec(Alive);
  inherited;
end;

function TCounted.Value: Integer;
begin
  Result := FValue;
end;

procedure Check(Cond: Boolean; Code: Integer);
begin
  if not Cond then
    begin
      WriteLn('failed ', Code);
      Halt(Code);
    end;
end;

procedure Loop;
begin
  for var I := 1 to 3 do
    begin
      { no initialization: empty at every iteration }
      var S: string;
      var A: array of Integer;
      Check((S = '') and (Length(A) = 0), 1);
      S := 'iteration ' + IntToStr(I);
      SetLength(A, I);
      var Intf: ICounted := TCounted.Create(I);
      Check(Intf.Value = I, 2);
    end;
end;

function EarlyExit(N: Integer): string;
begin
  var Text := 'value ' + IntToStr(N);
  var Obj: ICounted := TCounted.Create(N);
  if N > 0 then
    begin
      Result := Text;
      Exit;
    end;
  Result := '';
end;

procedure Raises;
begin
  var Text := 'will be finalized';
  var Obj: ICounted := TCounted.Create(1);
  raise Exception.Create(Text);
end;

begin
  {$if declared(HaltOnNotReleased)}
  HaltOnNotReleased := True;
  {$endif}
  Loop;
  Check(Alive = 0, 3);
  Check(EarlyExit(5) = 'value 5', 4);
  Check(Alive = 0, 5);
  try
    Raises;
  except
    on E: Exception do
      Check(E.Message = 'will be finalized', 6);
  end;
  Check(Alive = 0, 7);
  WriteLn('ok');
end.
