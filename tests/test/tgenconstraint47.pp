{ %FAIL }
{ the constraint still applies to the specialization }
program tgenconstraint47;

{$mode objfpc}{$H+}

uses
  ugenconstraint41;

begin
  specialize MakeBox<LongInt>(1);
end.
