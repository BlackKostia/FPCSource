{ %norun }
{ %opt='-dtest$FPCCPU' '-dtest$FPCOS' '-dtest$FPCCPUtest' '-dtest$FPCOStest' }
{ the single quotes keep the $ literal both when dotest runs the compiler
  through a shell and when it uses TProcess (no shell, since 2024), where
  a backslash escape would reach the compiler }

begin
{ test the most frequent combinations }
{$ifdef CPUX86_64}
{$ifdef testx86_64}
  writeln('ok 1');
{$else testx86_64}
  {$error default replacements failed}
{$endif testx86_64}
{$ifdef testx86_64test}
  writeln('ok 2');
{$else testx86_64test}
  {$error default replacements failed}
{$endif testx86_64test}
{$endif CPUX86_64}

{$ifdef CPUAARCH64}
{$ifdef testaarch64}
  writeln('ok 1');
{$else testaarch64}
  {$error default replacements failed}
{$endif testaarch64}
{$ifdef testaarch64test}
  writeln('ok 2');
{$else testaarch64test}
  {$error default replacements failed}
{$endif testaarch64test}
{$endif CPUAARCH64}

{$ifdef LINUX}
{$ifdef testlinux}
  writeln('ok 1');
{$else testlinux}
  {$error default replacements failed}
{$endif testlinux}
{$ifdef testlinuxtest}
  writeln('ok 2');
{$else testlinuxtest}
  {$error default replacements failed}
{$endif testlinuxtest}
{$endif LINUX}
end.
