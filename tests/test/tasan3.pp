{ %FAIL }
{ %OPT=-fsanitize=address -fsanitize=thread }
{ %TARGET=linux }
{ %CPU=x86_64 }
{ the two sanitizers cannot be combined }
program tasan3;

begin
end.
