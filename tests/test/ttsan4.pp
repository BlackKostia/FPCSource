{ %OPT=-fsanitize=thread }
{ %TARGET=linux }
{ %CPU=x86_64 }
{ %NORUN }
{ a program using an instrumented unit }
program ttsan4;

{$mode objfpc}

uses
  {$ifdef unix}cthreads,{$endif} utsan4;

begin
  Touch;
end.
