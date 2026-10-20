{ %FAIL }
{ specializations of a nocopy generic record are not copyable }
program tnocopy15;

{$mode objfpc}

uses
  unocopy2;

var
  a, b: specialize TBox<LongInt>;
begin
  b := a;
end.
