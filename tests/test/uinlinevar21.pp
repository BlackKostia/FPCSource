{ unit for tinlinevar21 }
{$mode objfpc}{$H+}
{$modeswitch inlinevars}
unit uinlinevar21;

interface

var
  InitValue: string;

generic function JoinTwice<T>(const A: T): string;
function Square(X: Integer): Integer; inline;

implementation

generic function JoinTwice<T>(const A: T): string;
begin
  var S: string;
  WriteStr(S, A);
  var Twice := S + S;
  Result := Twice;
end;

function Square(X: Integer): Integer; inline;
begin
  var R := X * X;
  Result := R;
end;

initialization
  begin
    var Part := 'init';
    InitValue := Part + 'ialized';
  end;
end.
