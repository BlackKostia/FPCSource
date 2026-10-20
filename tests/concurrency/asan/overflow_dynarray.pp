{ EXPECT: heap-buffer-overflow
  ACCESS: WRITE of size 4 }
program overflow_dynarray;
{$mode objfpc}{$R-}
var
  A: array of LongInt;
  I, N: Integer;
begin
  N := 5;
  SetLength(A, N);
  for I := 0 to N do
    A[I] := I * 3; {ERR}
  WriteLn(A[0]);
end.
