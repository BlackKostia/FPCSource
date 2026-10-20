unit unocopy2;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

type
  generic TBox<T> = record
    Value: T;
    function Move: TBox;
  end nocopy;

  TPlain = record
    Value: LongInt;
  end nocopy;

generic function MakeBox<T>(const aValue: T): specialize TBox<T>;

implementation

function TBox.Move: TBox;
begin
  Result.Value := Value;
  Value := Default(T);
end;

generic function MakeBox<T>(const aValue: T): specialize TBox<T>;
begin
  Result.Value := aValue;
end;

end.
