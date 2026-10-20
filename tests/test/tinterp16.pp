{ %OPT=-gh }
{ {$modeswitch interpolation} with multilinestrings: $`...` over several
  lines, the line endings of $MULTILINESTRINGLINEENDING, expressions on
  every line, escapes }
{$mode objfpc}{$H+}
{$modeswitch interpolation}
{$modeswitch multilinestrings}
program tinterp16;

uses
  SysUtils;

var
  Id: Integer;
  Customer, S: string;
  Total: Double;

procedure Check(const Got, Expected: string; Code: Integer);
begin
  if Got <> Expected then
    begin
      WriteLn('failed ', Code, ': got "', StringReplace(Got, #10, '\n', [rfReplaceAll]),
        '" expected "', StringReplace(Expected, #10, '\n', [rfReplaceAll]), '"');
      Halt(Code);
    end;
end;

begin
  Id := 1042;
  Customer := 'Olena';
  Total := 1234.5;

{$MULTILINESTRINGLINEENDING LF}
  S := $`<tr>
  <td>{Id}</td>
  <td>{Customer:8}</td>
  <td>{Total:0:2}</td>
</tr>`;
  Check(S, '<tr>'#10'  <td>1042</td>'#10'  <td>   Olena</td>'#10'  <td>1234.50</td>'#10'</tr>', 1);

  { only strings: concatenation }
  S := $`Dear {Customer},
thank you.`;
  Check(S, 'Dear Olena,'#10'thank you.', 2);

  { an empty line, a line starting with an expression, a line with an
    expression only }
  S := $`a

{Id} b
{Customer}
`;
  Check(S, 'a'#10#10'1042 b'#10'Olena'#10, 3);

{$MULTILINESTRINGLINEENDING CRLF}
  S := $`x {Id}
y`;
  Check(S, 'x 1042'#13#10'y', 4);

{$MULTILINESTRINGLINEENDING CR}
  S := $`p
q`;
  Check(S, 'p'#13'q', 5);

{$MULTILINESTRINGLINEENDING PLATFORM}
  S := $`m
n`;
  Check(S, 'm' + LineEnding + 'n', 6);

{$MULTILINESTRINGLINEENDING LF}
  { apostrophes are characters, `` is a backtick, braces are doubled }
  S := $`it's {{ok}} ``{Customer}``
'quoted' {UpperCase('x')}`;
  Check(S, 'it''s {ok} `Olena`'#10'''quoted'' X', 7);

  { on one line and without expressions }
  Check($`one {Id}`, 'one 1042', 8);
  Check($`two
lines`, 'two'#10'lines', 9);

  { as an argument }
  try
    raise Exception.Create($`line
{Id}`);
  except
    on E: Exception do
      Check(E.Message, 'line'#10'1042', 10);
  end;
  WriteLn('ok');
end.
