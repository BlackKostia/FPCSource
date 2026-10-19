{ the compiler announces support for constrained generic forward
  declarations (see tgenconstraint41 and following) }
program tgenconstraint58;

begin
{$ifndef FPC_HAS_CONSTRAINED_GENERIC_FORWARD}
  Halt(1);
{$endif}
  Writeln('ok');
end.
