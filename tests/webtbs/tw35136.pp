{ %opt=-Miso }
program p;
var f: text;
begin
    rewrite(f);
    f^ := 'a';
    put(f);
    reset(f);
    if eof(f) then writeln('premature eof');
    writeln(f^);
    if eof(f) then writeln('premature eof');
    writeln(f^);
    if eof(f) then writeln('premature eof');
    get(f);
    { ISO 7185: the last line has no line end, so an end of line is implied
      before the end of the file (see also tw40444) }
    if not eoln(f) then begin writeln('eoln should be set, but isn''t'); halt(1); end;
    if eof(f) then begin writeln('premature eof at the implied end of line'); halt(1); end;
    get(f);
    if eof(f) then writeln('eof correctly set') else begin writeln('eof should be set, but isn''t'); halt(1); end;
end.
