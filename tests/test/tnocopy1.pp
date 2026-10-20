{ allowed operations on a record type declared "nocopy" }
program tnocopy1;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

type
  TOwner = record
    Value: LongInt;
    class operator Initialize(var a: TOwner);
    function Move: TOwner;
  end nocopy;

  THolder = class
    Item: TOwner;
  end;

  { "nocopy" is not a reserved word }
  nocopy = LongInt;

class operator TOwner.Initialize(var a: TOwner);
begin
  a.Value := 0;
end;

function TOwner.Move: TOwner;
begin
  Result.Value := Value;
  Value := 0;
end;

function Make(aValue: LongInt): TOwner;
begin
  Result.Value := aValue;
end;

function ReadConst(const a: TOwner): LongInt;
begin
  Result := a.Value;
end;

function ReadConstRef(constref a: TOwner): LongInt;
begin
  Result := a.Value;
end;

procedure Bump(var a: TOwner);
begin
  Inc(a.Value);
end;

procedure Fill(out a: TOwner);
begin
  a.Value := 5;
end;

var
  a, b: TOwner;
  arr, arr2: array of TOwner;
  h: THolder;
  n: nocopy;
begin
  { function results are built in the destination }
  a := Make(3);
  if a.Value <> 3 then
    Halt(1);
  b := a.Move;
  if (b.Value <> 3) or (a.Value <> 0) then
    Halt(2);
  a := Default(TOwner);
  if (ReadConst(b) <> 3) or (ReadConstRef(b) <> 3) then
    Halt(3);
  Bump(b);
  Fill(a);
  if (b.Value <> 4) or (a.Value <> 5) then
    Halt(4);
  { growing an array moves, assigning a dynamic array shares it }
  SetLength(arr, 2);
  arr[1] := Make(9);
  SetLength(arr, 10);
  arr2 := arr;
  if arr2[1].Value <> 9 then
    Halt(5);
  { classes are not copied }
  h := THolder.Create;
  h.Item := Make(7);
  if h.Item.Value <> 7 then
    Halt(6);
  h.Free;
  n := 1;
  if n <> 1 then
    Halt(7);
{$ifndef FPC_HAS_NOCOPY_TYPES}
  Halt(8);
{$endif}
  Writeln('ok');
end.
