{ EXPECT: heap-buffer-overflow
  STACK: INNER OUTER
  the report shows the call chain of the bad access }
program overflow_stack;
{$mode objfpc}
var
  Data: PLongInt;
function Inner(I: Integer): LongInt;
begin
  Result := Data[I]; {ERR}
end;
function Outer(N: Integer): LongInt;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to N do
    Result := Result + Inner(I);
end;
begin
  Data := GetMem(4 * SizeOf(LongInt));
  FillChar(Data^, 4 * SizeOf(LongInt), 0);
  WriteLn(Outer(4));
end.
