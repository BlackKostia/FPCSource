{ %norun }
{ %needlibrary }
{ %target=linux }

{ Library for ttlsvar1b: threadvars of the library, of a unit compiled
  with it, and of the RTL (exception handling) used from several threads }
library ttlsvar1a;

{$mode objfpc}

uses
  cthreads, sysutils, utlsvar1;

threadvar
  tvLibCounter: Integer;

// Bumps the threadvars of the library and of the unit
function TouchThreadVars: Integer; cdecl;

begin
  Inc(tvLibCounter);
  Result:=tvLibCounter*100+BumpUnitCounter;
end;


// Raises and catches an exception: uses the RTL's threadvars
function RaiseAndCatch: Integer; cdecl;

begin
  Result:=0;
  try
    raise Exception.Create('tls');
  except
    on E: Exception do
      if E.Message='tls' then
        Result:=1;
  end;
end;


exports
  TouchThreadVars,
  RaiseAndCatch;

end.
