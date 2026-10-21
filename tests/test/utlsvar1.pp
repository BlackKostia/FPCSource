{ Unit with a threadvar, compiled as part of library ttlsvar1a without -Cg }
unit utlsvar1;

{$mode objfpc}

interface

threadvar
  tvUnitCounter: Integer;

// Increments the threadvar of the calling thread and returns its new value
function BumpUnitCounter: Integer;

implementation

function BumpUnitCounter: Integer;

begin
  Inc(tvUnitCounter);
  Result:=tvUnitCounter;
end;

end.
