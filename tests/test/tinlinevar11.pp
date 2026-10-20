{ %FAIL }
{ the type of nil cannot be inferred }
{$mode objfpc}
{$modeswitch inlinevars}
program tinlinevar11;
begin
  var P := nil;
end.
