{ %FAIL }
{ %OPT=-fsanitize=memory }
{ only -fsanitize=thread is supported by the native code generator }
program ttsan5;

begin
end.
