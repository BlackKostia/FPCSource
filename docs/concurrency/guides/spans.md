# Посібник користувача: зрізи пам'яті `TSpan<T>` і `TReadOnlySpan<T>`

Модуль `spans` (`System.Spans` у dotted-збірці), пакет `rtl-objpas`.
Розділ 3.2 дорожньої карти ([roadmap.md](../roadmap.md)), рішення —
[ADR-0009](../adr/0009-spans.md).

## 1. Навіщо

Щоб передати частину масиву в процедуру, у Pascal зазвичай або копіюють її
(`Copy(A, Start, Count)` — алокація в купі), або передають трійку
«масив, початок, кількість», за якою стежить сам програміст. Відкриті
масиви (`array of T`) завжди починаються з першого елемента і не можуть
бути полем чи змінною.

Зріз — це пара «вказівник + довжина» (`Data`, `Length`): вікно в будь-який
неперервний діапазон статичного чи динамічного масиву, рядка або `TBytes`,
**без копіювання й без алокацій**, з перевіркою меж на кожному доступі.

```pascal
uses spans;
type
  TDoubleSpan = specialize TSpan<Double>;

function SumOf(const aValues: TDoubleSpan.TReadOnly): Double;
var
  X: Double;
begin
  Result := 0;
  for X in aValues do
    Result := Result + X;
end;

var
  Data: array of Double;
begin
  ...
  WriteLn(SumOf(TDoubleSpan.Create(Data).Slice(100, 50)));   // без копії
end;
```

| Тип | Доступ | Аналог |
|---|---|---|
| `TReadOnlySpan<T>` | лише читання | `ReadOnlySpan<T>` у .NET, `&[T]` у Rust |
| `TSpan<T>` | читання й запис; неявно перетворюється на `TReadOnlySpan<T>` | `Span<T>`, `&mut [T]` |

Готові спеціалізації: `TByteSpan`/`TReadOnlyByteSpan`,
`TAnsiCharSpan`/`TReadOnlyAnsiCharSpan`, `TWideCharSpan`/`TReadOnlyWideCharSpan`.

## 2. Створення

| Виклик | Що отримуємо |
|---|---|
| `TSpan.Create(Arr)` | увесь статичний чи динамічний масив (`var`-параметр: без копії) |
| `TSpan.Create(Arr, Start, Count)` | частину масиву; `ERangeError`, якщо діапазон виходить за межі |
| `TReadOnlySpan.Create(Arr)` / `(Arr, Start, Count)` | те саме лише для читання (`const`) |
| `TSpan.Create(P, Len)` | `Len` елементів за вказівником `P` — **без перевірки** джерела |
| `SpanOf(S)` | символи `AnsiString`/`RawByteString` чи `UnicodeString` (лише читання) |
| `MutableSpanOf(S)` | символи рядка для запису; спершу робить рядок унікальним (`UniqueString`) |
| `TSpan.Create(Bytes)` для `TBytes` | байти (`TBytes` — динамічний масив `Byte`) |

## 3. Операції

| Член | Опис |
|---|---|
| `Items[I]` (за замовчуванням: `S[I]`) | елемент; `ERangeError` при `I < 0` або `I >= Length` |
| `Length`, `IsEmpty`, `Data` | довжина, порожність, вказівник на перший елемент |
| `Slice(Start)`, `Slice(Start, Count)` | підзріз; `ERangeError`, якщо не всередині |
| `Chunk(I, N)` | частина `I` з `N` майже рівних неперетинних частин, що разом покривають зріз |
| `Overlaps(Other)` | чи мають два зрізи спільні елементи |
| `for X in S do` | обхід без перевірок меж (найшвидший) |
| `ToArray` | копія елементів у новий динамічний масив |
| `TSpan.CopyFrom(Src)` | копіювання на початок зрізу; перекриття обробляється (як `memmove`); `ERangeError`, якщо не влазить |
| `TSpan.Fill(V)` | заповнити значенням |
| `TSpan.AsReadOnly`, неявне `:=` | перетворення на `TReadOnlySpan<T>` |

`CopyFrom`, `Fill` і `ToArray` присвоюють елементи по одному, тож для
керованих типів (рядки, інтерфейси, динамічні масиви) лічильники посилань
коректні.

## 4. Перевірка меж

Межі перевіряються **завжди**: в `Items`, `Slice`, `Chunk`, `Create` з
діапазоном і `CopyFrom`. Перевірки написано так, що вони не переповнюються
навіть для `Slice(High(SizeInt), High(SizeInt))`.

Дорожня карта передбачала перевірку «при `-Cr`», але для дженериків це
неможливо: код методів `TSpan<T>` компілюється з налаштуваннями модуля
`spans` (RTL збирається без `-Cr`), а не модуля, що спеціалізує тип —
перевірено експериментом, див. ADR-0009. Тому перевірки ввімкнено завжди,
як у .NET і Rust. Ціна — одне порівняння на доступ; для гарячих циклів
є `for..in` (без перевірок) і `Data` (сирий вказівник).

## 5. Паралельна обробка

Зрізи, що не перекриваються, можна одночасно використовувати з різних
потоків: кожен потік пише лише у свою пам'ять, синхронізація не потрібна.
`Chunk(I, N)` дає саме такі частини:

```pascal
Whole := TDoubleSpan.Create(Data);
TParallel.&For(0, Parts - 1,
  procedure(aIndex: Integer)
  var
    Chunk: TDoubleSpan;
    J: SizeInt;
  begin
    Chunk := Whole.Chunk(aIndex, Parts);   // свій шматок у кожної задачі
    for J := 0 to Chunk.Length - 1 do
      Chunk[J] := Chunk[J] * 2;
  end);
```

Гарантії `Chunk(I, N)`: частини йдуть підряд, не перекриваються, разом
покривають увесь зріз, розміри відрізняються щонайбільше на один елемент;
при `N > Length` частина частин порожня. Перевірено тестом для всіх довжин
0..40 і кількостей частин 1..12, а паралельне заповнення 8 потоками —
Helgrind (0 повідомлень).

Сам зріз — запис із двох полів; змінна-зріз, у яку пишуть з одного потоку й
читають з іншого, потребує синхронізації, як і будь-яка інша змінна.

## 6. Час життя — головне правило

Зріз **не володіє** елементами й не утримує джерело живим:

- не використовуйте зріз після того, як масив звільнено чи змінено його
  довжину (`SetLength` може перенести масив в іншу пам'ять);
- зріз рядка стає недійсним після зміни рядка (копіювання при записі
  переносить символи), тому для запису — `MutableSpanOf`, і потім не
  змінюйте рядок інакше, ніж через зріз;
- не створюйте зріз тимчасового значення: результату функції, що повертає
  масив, чи конструктора `[1, 2, 3]` — після оператора пам'ять звільнено.

Ці помилки перевірка меж не ловить — так само, як у C# поза `ref struct`.

## 7. Тести й приклад

- fpcunit: `packages/rtl-objpas/tests/utcspans.pp` (35 тестів:
  `TTestSpanCreate`, `TTestSpanAccess`, `TTestSpanSlice`, `TTestSpanChunk`,
  `TTestSpanOps`, `TTestSpanParallel`), входять до `testrunner.rtlobjpas.pp`.
  ```sh
  tests/concurrency/build-spans.sh                 # збірка + запуск
  tests/concurrency/build-spans.sh "" -gh          # з heaptrc (0 витоків)
  tests/concurrency/build-spans.sh "" -Cr -Co -Ct  # з перевірками діапазону/переповнення
  ```
- Приклад: [`examples/spans_parallel.pp`](../examples/spans_parallel.pp).
- Довідник API у форматі fpdoc: `packages/rtl-objpas/xml/spans.xml`.
