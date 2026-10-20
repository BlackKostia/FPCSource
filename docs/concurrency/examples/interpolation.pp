{ Interpolated strings ({$modeswitch interpolation}): $'Text {Expr}' with
  the formatting of WriteStr ({Expr:Width}, {Expr:Width:Precision}),
  checked by the compiler; $`...` over several lines (multilinestrings).
  See docs/concurrency/language/interpolation.md }
program interpolation;

{$mode objfpc}{$H+}
{$modeswitch interpolation}
{$modeswitch multilinestrings}
{$MULTILINESTRINGLINEENDING LF}

uses
  SysUtils;

type
  TStatus = (stNew, stPaid, stShipped);

  TOrder = record
    Id: Integer;
    Customer: string;
    Total: Double;
    Status: TStatus;
    Urgent: Boolean;
  end;

const
  Orders: array[0..2] of TOrder = (
    (Id: 1042; Customer: 'Olena'; Total: 1234.5; Status: stPaid; Urgent: True),
    (Id: 1043; Customer: 'Taras'; Total: 99.99; Status: stNew; Urgent: False),
    (Id: 1044; Customer: 'Iryna'; Total: 15000; Status: stShipped; Urgent: False));

function Describe(const O: TOrder): string;
begin
  Result := $'Order #{O.Id} from {O.Customer}: {O.Total:0:2} UAH, {O.Status}';
end;

procedure PrintTable;
var
  Sum: Double;
  I: Integer;
begin
  WriteLn($'|{'Id':6}|{'Customer':10}|{'Total':10}|');
  Sum := 0;
  for I := Low(Orders) to High(Orders) do
    with Orders[I] do
      begin
        WriteLn($'|{Id:6}|{Customer:10}|{Total:10:2}|');
        Sum := Sum + Total;
      end;
  WriteLn($'|{'':6}|{'sum':10}|{Sum:10:2}|');
end;

{ a multi-line template }
function ToHtml(const O: TOrder): string;
begin
  Result := $`<tr class="{O.Status}">
  <td>{O.Id}</td>
  <td>{O.Customer}</td>
  <td>{O.Total:0:2}</td>
</tr>`;
end;

procedure Withdraw(const O: TOrder; Amount: Double);
begin
  if Amount > O.Total then
    raise Exception.Create($'Order #{O.Id}: {Amount:0:2} is more than {O.Total:0:2}');
end;

var
  O: TOrder;

begin
  for O in Orders do
    WriteLn(Describe(O));
  WriteLn;
  PrintTable;
  WriteLn;
  { any expression, also function calls and string constants }
  WriteLn($'Hex id: {IntToHex(Orders[0].Id, 4)}, upper: {UpperCase(Orders[1].Customer)}');
  WriteLn($'Urgent: {Orders[0].Urgent}, orders: {Length(Orders)}');
  { braces and apostrophes as characters }
  WriteLn($'JSON: {{"id": {Orders[0].Id}, "name": "{Orders[0].Customer}"}}, it''s ok');
  WriteLn(ToHtml(Orders[0]));
  try
    Withdraw(Orders[1], 500);
  except
    on E: Exception do
      WriteLn($'Error: {E.Message}');
  end;
end.
