# Посібник користувача: змінні за місцем використання (`{$modeswitch inlinevars}`)

Розділ 2.3 дорожньої карти ([roadmap.md](../roadmap.md)). Перемикач форку,
синтаксис сумісний із Delphi 10.3+.

## 1. Навіщо

У класичному Pascal усі змінні оголошують у секції `var` перед `begin`. Для
довгих узагальнених типів це означає писати тип двічі й далеко від місця
використання:

```pascal
var
  Cache: specialize TDictionary<string, TAccountRecord>;
  Channel: specialize TChannel<TOrderTransactionRecord>;
begin
  ...
  Cache := specialize TDictionary<string, TAccountRecord>.Create;
  Channel := specialize TChannel<TOrderTransactionRecord>.Create(4096);
```

З `{$modeswitch inlinevars}` змінну оголошують там, де вона потрібна, а тип
компілятор виводить з ініціалізації:

```pascal
{$modeswitch inlinevars}
...
  var Cache := specialize TDictionary<string, TAccountRecord>.Create;
  var Channel := specialize TChannel<TOrderTransactionRecord>.Create(4096);
```

Типізація лишається **статичною**: тип визначається один раз під час
компіляції й більше не змінюється (`var X := 5; X := 'a'` — помилка
компіляції, як і з явним `Integer`). Це не `Variant` і не динамічна
типізація.

## 2. Увімкнення

```pascal
{$mode objfpc}{$H+}
{$modeswitch inlinevars}
```

Без перемикача компілятор поводиться як FPC: `var` у тілі підпрограми —
синтаксична помилка. У режимі `{$mode delphi}` перемикач теж потрібно
вмикати явно.

## 3. Синтаксис

Оголошення — окремий оператор у списку операторів (`begin..end`,
`repeat..until`, частини `try`):

```pascal
var Count := 0;                    // тип виводиться: Integer
var Name: string := 'Pascal';      // явний тип з ініціалізацією
var Left, Right: Integer;          // кілька змінних без ініціалізації
var List := TStringList.Create;    // тип: TStringList
```

Змінна циклу `for`:

```pascal
for var I := 0 to High(Items) do         // тип з початкового значення
  Process(Items[I]);
for var I: Int64 := Big downto 1 do      // явний тип
  ...
for var Item in List do                  // тип елемента колекції
  WriteLn(Item);
```

Ініціалізація з кількома змінними (`var A, B: Integer := 0;`), оголошення
без типу й без ініціалізації (`var X;`) і оголошення як єдиний оператор
`if`/`while` (`if C then var X := 1;`) — помилки компіляції.

## 4. Виведення типу

| Ініціалізація | Тип змінної |
|---|---|
| ціла константа `5`, `-3` | `Integer` (`LongInt`); поза його межами — `Int64` (або `QWord`) |
| рядкова константа `'text'` | `AnsiString` з `{$H+}`, `UnicodeString` з `{$modeswitch unicodestrings}`, `ShortString` з `{$H-}` |
| дійсна константа `2.5` | `Extended` (як `const X = 2.5` у FPC) |
| `True`, `Green`, `'c'` (символ) | `Boolean`, тип переліку, `Char` |
| виклик функції, вираз | тип результату виразу |
| `TStringList.Create` | `TStringList` |
| `nil`, `[1, 2, 3]`, виклик процедури | не виводиться — вкажіть тип явно |

`for var X in Колекція` бере тип елемента:

| Колекція | Тип `X` |
|---|---|
| статичний чи динамічний масив | тип елемента |
| `string`/`AnsiString`/`ShortString` | `Char`; `UnicodeString`/`WideString` — `WideChar` |
| множина, `[Red, Blue]` | тип елемента |
| тип переліку `TColor` | `TColor` |
| `[10, 20, 30]` | `Integer` |
| клас чи запис із `GetEnumerator` (`TList<T>`, `TStringList` …) | тип властивості `Current` нумератора |

Для `operator Enumerator` тип не виводиться, його треба вказати
(`for var X: T in ...`).

## 5. Область видимості

- Змінна видима від оголошення до кінця списку операторів, у якому
  оголошена: `begin..end`, `repeat..until` (разом з умовою `until`), окремо
  частина `try`, частина `finally`, частина `except`.
- Змінна `for var` видима лише в тілі циклу.
- Ініціалізація не бачить змінної, яку ініціалізує: `var X := X + 1`
  бере зовнішню `X`.
- В одному блоці ім'я не можна повторити, як і ім'я параметра чи звичайної
  локальної змінної тієї самої підпрограми («Duplicate identifier»). У
  сусідніх блоках і циклах те саме ім'я дозволене, зокрема з іншим типом:

```pascal
for var I := 1 to 10 do ...
for var I := 'a' to 'z' do ...   // нова змінна I типу Char
```

- Змінна блоку затіняє глобальну змінну з тим самим ім'ям лише до кінця
  блоку.

## 6. Час життя й керовані типи

Inline-змінна — звичайна локальна змінна підпрограми: вона розміщена в її
кадрі й фіналізується разом з іншими локальними змінними — при виході з
підпрограми, зокрема через `Exit` і виняток. Відмінність від Delphi: рядок,
динамічний масив чи інтерфейс, оголошений у вкладеному блоці, звільняється
не в кінці блоку, а в кінці підпрограми (або коли змінну перезаписують).

У тілі головної програми та в секціях `initialization`/`finalization`
модуля підпрограми зі своїм кадром немає, тому там inline-змінна —
прихована статична змінна модуля (видимість та сама, до кінця блоку).
Вкладені й анонімні функції звертаються до неї напряму, як до глобальної;
рядки й інші керовані типи фіналізуються під час завершення програми чи
модуля.

Змінна керованого типу без ініціалізації, оголошена в циклі, на кожній
ітерації починає порожньою (`''`, `nil`). Змінна некерованого типу без
ініціалізації не визначена, як і звичайна локальна змінна (компілятор
попереджає, якщо її прочитано до присвоєння).

Налагоджувач (`-gw`, `-gw3`, `-gs`) показує inline-змінні під їхніми
іменами.

## 7. Приклади

### Підрахунок слів

```pascal
{$mode objfpc}{$H+}
{$modeswitch inlinevars}
uses SysUtils, Classes, Generics.Collections;

procedure CountWords(const Text: string);
begin
  var Counts := specialize TDictionary<string, Integer>.Create;
  try
    for var Word in Text.Split([' ', ',', '.'], TStringSplitOptions.ExcludeEmpty) do
      begin
        var Key := LowerCase(Word);
        var N: Integer;
        if not Counts.TryGetValue(Key, N) then
          N := 0;
        Counts.AddOrSetValue(Key, N + 1);
      end;
    for var Pair in Counts do
      WriteLn(Pair.Key, ': ', Pair.Value);
  finally
    Counts.Free;
  end;
end;
```

### Разом з `{$modeswitch implicitgenerics}`

Без `specialize` і з виведенням типів дженериків
([implicit-generics.md](implicit-generics.md)):

```pascal
{$mode objfpc}{$H+}
{$modeswitch implicitgenerics}
{$modeswitch inlinevars}
...
  var Cache := TDictionary<string, TAccountRecord>.Create;
  var Results := TList<Int64>.Create;
  for var Account in Cache.Values do
    Results.Add(Account.Balance);
```

### Розпакування кортежу (`{$modeswitch tuples}`)

З `inlinevars` змінні `var (A, B) := ...` мають ту саму область видимості
блоку:

```pascal
{$modeswitch tuples}
{$modeswitch inlinevars}
...
  for var I := 1 to 10 do
    begin
      var (Quot, Rem) := DivRem(I * 7, 3);
      WriteLn(Quot, ' ', Rem);
    end;
```

Повний приклад — [`examples/inline_vars.pp`](../examples/inline_vars.pp).

## 8. Тести

`tests/test/tinlinevar1`–`5`, `tinlinevar21` (з модулем `uinlinevar21`) —
виведення типів, області видимості, `for var` для всіх видів колекцій,
керовані типи без витоків (`-gh`), винятки й `Exit`, `repeat`, `try`,
`case`, вкладені й узагальнені підпрограми, анонімні функції, `inline`,
`initialization` модуля, `-gw -O3`, кортежі; `tinlinevar26` — ініціалізація
`var X := …` і `var (A, B) := …` не дає попередження про неініціалізовану
змінну; `tinlinevar22` — разом із
класичними секціями `var` (глобальною, підпрограми, вкладеної підпрограми);
`tinlinevar25` (з модулем `uinlinevar25`) — змінні головної програми та
`initialization` модуля, захоплені анонімними функціями.
`tinlinevar6`–`20`, `23`, `24` (`{%FAIL}`) — помилки: без перемикача, видимість після
блоку, циклу, `repeat`, у `finally`, оголошення як єдиний оператор `if`,
без типу, `nil` і `[..]`, ініціалізація кількох змінних, повторне ім'я,
ім'я параметра чи змінної з секції `var` тієї самої підпрограми (також у
вкладеному блоці), зміна типу, змінна у власній ініціалізації, присвоєння
змінній циклу.
