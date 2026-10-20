{ %skiptarget=$nosharedlib }
{ %NEEDLIBRARY }
{ %delfiles=tlibrary1 }

{ Test program to test linking to fpc library }

{$ifdef mswindows}
 {$define supported}
{$endif mswindows}
{$ifdef Unix}
 {$define supported}
{$endif Unix}
{$ifndef fpc}
   {$define supported}
{$endif}

{$ifdef supported}

{ a program that uses shared libraries on linux has to link to glibc:
  the dynamic loader of current glibc versions looks up calloc etc. in
  libc (as in tlibrary2 and the other library tests) }
{$if (FPC_FULLVERSION<=30301) and defined(linux)}
  uses
    initc;
{$endif (FPC_FULLVERSION<=30301) and defined(linux)}

const
{$ifdef windows}
  libname='tlibrary1.dll';
{$else}
  libname='tlibrary1';
  {$linklib tlibrary1}
{$endif}

procedure test;external libname name 'TestName';

begin
  if islibrary then
    halt(3);
  if moduleislib then
    halt(4);
  test;
end.
{$else not supported}
begin
  Writeln('Dummy test because target does not support libraries');
end.
{$endif not supported}
