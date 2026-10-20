{ Inline variables ({$modeswitch inlinevars}): declared where they are
  needed, the type inferred from the initialization or the collection.
  See docs/concurrency/language/inline-vars.md }
program inline_vars;

{$mode objfpc}{$H+}
{$modeswitch implicitgenerics}
{$modeswitch inlinevars}
{$modeswitch tuples}

uses
  SysUtils, Generics.Collections;

type
  TAccount = record
    Owner: string;
    Balance: Int64;
  end;

function DivRem(A, B: Integer): (Integer, Integer);
begin
  Result := (Integer(A div B), Integer(A mod B));
end;

procedure CountWords(const Text: string);
begin
  var Counts := TDictionary<string, Integer>.Create;
  try
    for var Word in Text.Split([' ', ',', '.'], TStringSplitOptions.ExcludeEmpty) do
      begin
        var Key := LowerCase(Word);
        var N: Integer;
        if not Counts.TryGetValue(Key, N) then
          N := 0;
        Counts.AddOrSetValue(Key, N + 1);
      end;
    var Keys := TList<string>.Create(Counts.Keys);
    try
      Keys.Sort;
      for var Key in Keys do
        WriteLn('  ', Key, ': ', Counts[Key]);
    finally
      Keys.Free;
    end;
  finally
    Counts.Free;
  end;
end;

procedure Accounts;
begin
  var Cache := TDictionary<string, TAccount>.Create;
  try
    for var I := 1 to 3 do
      begin
        var Account: TAccount;
        Account.Owner := 'client' + IntToStr(I);
        Account.Balance := I * 1000;
        Cache.Add(Account.Owner, Account);
      end;
    var Total := 0;
    for var Account in Cache.Values do
      Inc(Total, Account.Balance);
    WriteLn('  accounts: ', Cache.Count, ', total balance: ', Total);
  finally
    Cache.Free;
  end;
end;

begin
  WriteLn('word count:');
  CountWords('The quick fox. The lazy dog, the end');

  WriteLn('accounts:');
  Accounts;

  WriteLn('letters:');
  Write('  ');
  { the same name I in the next loop, now of type Char }
  for var I := 'a' to 'e' do
    Write(I);
  WriteLn;

  WriteLn('tuples:');
  for var I := 1 to 3 do
    begin
      var (Quot, Rem) := DivRem(I * 7, 3);
      WriteLn('  ', I * 7, ' = 3 * ', Quot, ' + ', Rem);
    end;
end.
