{ %FAIL }
{ "nocopy" is only allowed for records }
program tnocopy21;

{$mode objfpc}

type
  TObj = class
  end nocopy;

begin
end.
