{ EXPECT: norace
  thread creation and join order the accesses }
program norace_join;
{$mode objfpc}
uses {$ifdef unix}cthreads,{$endif} SysUtils;
var
  Data: array of LongInt;
  Sum: Int64;
function Work(P: Pointer): PtrInt;
var
  I: Integer;
begin
  for I := 0 to High(Data) do
    Data[I] := Data[I] * 2;
  Result := 0;
end;
var
  T: TThreadID;
  I: Integer;
begin
  SetLength(Data, 1000);
  for I := 0 to High(Data) do
    Data[I] := I;
  T := BeginThread(@Work, nil);
  WaitForThreadTerminate(T, 0);
  CloseThread(T);
  Sum := 0;
  for I := 0 to High(Data) do
    Inc(Sum, Data[I]);
  WriteLn('sum=', Sum);
end.
