{ EXPECT: heap-use-after-free
  ACCESS: READ of size 8 }
program use_after_free;
{$mode objfpc}
type
  TData = class
    Value: Int64;
  end;
var
  D: TData;
begin
  D := TData.Create;
  D.Value := 42;
  D.Free;
  WriteLn(D.Value); {ERR}
end.
