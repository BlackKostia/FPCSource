{ unit of tinterp2: interpolated strings in a generic routine, a generic
  class, an inline routine and the initialization of the unit }
{$mode delphi}{$H+}
{$modeswitch interpolation}
unit uinterp2;

interface

type
  TBox<T> = class
  public
    Value: T;
    function Show(const Name: string): string;
  end;

var
  InitText: string;

function Tagged<T>(const Tag: string; const V: T): string;
function Pair(A, B: Integer): string; inline;

implementation

function TBox<T>.Show(const Name: string): string;
begin
  Result := $'{Name}=<{Value}>';
end;

function Tagged<T>(const Tag: string; const V: T): string;
begin
  Result := $'[{Tag}] {V}';
end;

function Pair(A, B: Integer): string;
begin
  Result := $'({A}, {B})';
end;

initialization
  InitText := $'unit {Pair(1, 2)}';
end.
