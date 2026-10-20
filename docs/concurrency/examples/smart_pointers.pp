program smart_pointers;
// Розумні вказівники модуля smartptrs: TScoped<T> (одноосібне володіння
// без try..finally), TArc<T> (спільне володіння між потоками з атомарним
// лічильником) і TWeak<T> (спостереження без володіння).
{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, System.Threading, smartptrs;

type
  TStringListScoped = specialize TScoped<TStringList>;
  TMemoryStreamScoped = specialize TScoped<TMemoryStream>;

  // Довідник, який читають кілька задач одночасно.
  TCatalog = class
    Names: TStringList;
    constructor Create;
    destructor Destroy; override;
  end;
  TCatalogArc = specialize TArc<TCatalog>;
  TCatalogWeak = specialize TWeak<TCatalog>;

constructor TCatalog.Create;
begin
  Names := TStringList.Create;
  Names.CommaText := 'alpha,beta,gamma,delta';
end;

destructor TCatalog.Destroy;
begin
  Names.Free;
  inherited Destroy;
end;

// 1. Локальний об'єкт без try..finally: Free викликається на виході.
function CountWords(const Text: string): Integer;
var
  Words: TStringListScoped;
begin
  Words.Reset(TStringList.Create);
  Words.Obj.Delimiter := ' ';
  Words.Obj.StrictDelimiter := True;
  Words.Obj.DelimitedText := Text;
  Result := Words.Obj.Count;
end;

// 2. Виняток посеред роботи: буфер однаково звільняється.
procedure BuildReport(Fail: Boolean);
var
  Buf: TMemoryStreamScoped;
  Line: string;
begin
  Buf.Reset(TMemoryStream.Create);
  Line := 'report';
  Buf.Obj.WriteBuffer(Line[1], Length(Line));
  if Fail then
    raise EInOutError.Create('disk full');
  WriteLn('  report size: ', Buf.Obj.Size);
end;

// 3. Передача володіння з функції: результат пишеться прямо в змінну
//    викликача, копіювання не відбувається.
function LoadLines(N: Integer): TStringListScoped;
var
  I: Integer;
begin
  Result.Reset(TStringList.Create);
  for I := 1 to N do
    Result.Obj.Add('line ' + IntToStr(I));
end;

// 4. Кожна задача володіє власною копією TArc. Анонімна функція захоплює
//    змінну, а не значення, тому копію створює параметр фабрики.
function StartLookup(Catalog: TCatalogArc; const Key: string): specialize IFuture<Integer>;
begin
  Result := TTask.specialize Future<Integer>(
    function: Integer
    begin
      Sleep(20);
      Result := Catalog.Obj.Names.IndexOf(Key);
    end);
end;

var
  Lines, Other: TStringListScoped;
  Catalog, Locked: TCatalogArc;
  Watch: TCatalogWeak;
  Lookups: array of specialize IFuture<Integer>;
  Keys: array of string;
  I: Integer;
begin
  WriteLn('1. TScoped instead of try..finally');
  WriteLn('  words: ', CountWords('the quick brown fox'));

  WriteLn('2. Exception safety');
  BuildReport(False);
  try
    BuildReport(True);
  except
    on E: EInOutError do
      WriteLn('  caught "', E.Message, '", buffer already freed');
  end;

  WriteLn('3. Ownership transfer');
  Lines := LoadLines(3);
  WriteLn('  lines: ', Lines.Obj.Count);
  Other := Lines.Move;                  // Lines порожній, Other — власник
  WriteLn('  after Move: Lines assigned=', Lines.IsAssigned,
    ', Other count=', Other.Obj.Count);
  // Lines := Other;  — помилка компіляції: TScoped оголошено "nocopy"
  //                    (зі старим компілятором — ESmartPtrError)

  WriteLn('4. TArc shared by tasks');
  Catalog := TCatalogArc.Create(TCatalog.Create);
  Keys := ['gamma', 'alpha', 'omega'];
  SetLength(Lookups, Length(Keys));
  for I := 0 to High(Keys) do
    Lookups[I] := StartLookup(Catalog, Keys[I]);
  WriteLn('  owners while tasks run: ', Catalog.UseCount > 1);
  Catalog.Reset;                        // головний потік більше не власник
  for I := 0 to High(Keys) do
    WriteLn('  ', Keys[I], ' -> ', Lookups[I].Value);

  WriteLn('5. TWeak observes without owning');
  Catalog := TCatalogArc.Create(TCatalog.Create);
  Watch := TCatalogWeak.Create(Catalog);
  if Watch.TryLock(Locked) then
    WriteLn('  locked, owners: ', Locked.UseCount);
  Locked.Reset;
  Catalog.Reset;                        // останній власник: Free тут
  WriteLn('  expired: ', Watch.Expired, ', lock succeeds: ', Watch.TryLock(Locked));
end.
