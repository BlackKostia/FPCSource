{ unit of tusing4: using in a unit routine, an inline routine, a generic
  routine and the initialization of the unit }
{$mode delphi}{$H+}
{$modeswitch using}
unit uusing4;

interface

uses
  Classes;

var
  InitCount: Integer;

function JoinLines(const A, B: string): string;
function CountLines(const S: string): Integer; inline;
function MakeAndName<T: TStrings>: string;

implementation

function JoinLines(const A, B: string): string;
begin
  using var L := TStringList.Create do
    begin
      L.Add(A);
      L.Add(B);
      L.LineBreak := ',';
      Result := L.Text;
    end;
end;

function CountLines(const S: string): Integer;
begin
  using var L := TStringList.Create do
    begin
      L.Text := S;
      Result := L.Count;
    end;
end;

function MakeAndName<T>: string;
begin
  using var R := T.Create do
    begin
      R.Add('1');
      Result := R.ClassName + R[0];
    end;
end;

initialization
  using var L := TStringList.Create do
    begin
      L.Add('x');
      InitCount := L.Count;
    end;
end.
