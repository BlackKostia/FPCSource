# Дорожня карта розвитку Free Pascal: конкурентоспроможність мови та бібліотек

Цей документ систематизує напрямки вдосконалення Free Pascal (компілятора, RTL, FCL та інструментарію), щоб мова залишалася конкурентною порівняно з сучасними системними та прикладними мовами (**Rust, Go, C#/.NET, C++20, сучасний Delphi**), зберігаючи свої головні переваги: миттєву компіляцію в нативний код, відсутність пауз GC, строгу типізацію та зворотну сумісність.

---

## 1. Сучасна багатопоточність та асинхронність (Фази 2–4 гілки `feature/concurrency`)

Після стабілізації `System.Threading` та `TThreadPool` (Фаза 1) для мережевих сервісів, GUI-застосунків та високонавантажених систем потрібні наступні рівні:

### 1.1. Неблокувальні продовження задач (`Continuations`) і кооперативне скасування
- **Проблема**: зараз отримання результату `IFuture<T>` або очікування `ITask` вимагає блокування потоку у `.Wait` чи `.Value`, а `ITask.Cancel` прив'язаний до окремої задачі.
- **Рішення**:
  - Додати методи `.ContinueWith(const AAction: TProc<ITask>): ITask` та типізований `.ThenBy<TResult>(...)` для побудови неблокувальних конвеєрів задач.
  - Ввести легковаговий токен скасування **`TCancellationToken` / `TCancellationTokenSource`**, який можна передавати в `TParallel.For`, `TTask.Run`, `IFuture<T>` та асинхронний I/O для узгодженого переривання дерева операцій.

### 1.2. Нові примітиви синхронізації в `SyncObjs` (Фаза 2)
- **`TCountdownEvent`** — легковагова синхронізація завершення динамічної кількості підзадач.
- **`TBarrier`** — пофазна синхронізація групи потоків для ітеративних паралельних алгоритмів (симуляції, обробка графів/матриць).
- **`TSlimReaderWriterLock`** — швидке блокування читання/запису в просторі користувача (на базі `futex` / атомарних операцій без важких системних викликів `pthread_rwlock`).
- **`TChannel<T>` (обмежені та необмежені потокобезпечні канали в стилі Go)** — передавання повідомлень між потоками за моделлю CSP (Communicating Sequential Processes) із підтримкою закриття (`Close`) та перебору `for Msg in Channel do`.

### 1.3. Масштабований асинхронний I/O — пакет `fcl-eventloop` (Фаза 3)
- Цикл подій на базі нативних механізмів Linux: **`io_uring` / `epoll`**
  (цільова платформа гілки — x86_64-linux, [ADR-0011](adr/0011-target-platform.md);
  бекенди `kqueue` і `IOCP` лежать у пакеті, але не підтримуються й не тестуються).
- Неблокувальні сокети, таймери, файлові операції та пайпи, здатні обслуговувати 100 000+ одночасних з'єднань на пулі з кількох робочих потоків.

### 1.4. Корутини та `async` / `await` у компіляторі (Фаза 4) [РЕАЛІЗОВАНО]
- **Крок 1 (бібліотечний)**: легковагові стекові корутини (fibers) `TFiber`, `generic TGenerator<T>` з підтримкою `for..in`, `generic TChannel<T>` CSP-канали та скінченні автомати `TTaskCompletionSource<T>`.
- **Крок 2 (у компіляторі `compiler/ppcx64`)**:
  - Директива/модифікатор `async;` для процедур і функцій з обов'язковою строгою перевіркою повернення `ITask` або `specialize IFuture<T>`.
  - Директива `{$ASYNCMODE AUTO|FIBER|STATEMACHINE}` для налаштування моделі диспетчеризації.
  - Оператор `await` із неблокуючим перемиканням контексту файбера через `TaskAwaitHook`.
  - Високорівневі методи `RunAsync<T>`, `SpawnAsync`, `AsyncSleep` у `fclasync`.
  - Повний набір із 10 порівняльних бенчмарків Pascal vs C# у `tests/concurrency/comparison/` (10/10 успішних тестів).

---


### 1.5. Дрібні задачі та fork-join — `System.Threading.ForkJoin` [РЕАЛІЗОВАНО]
- `TTask` — повноцінний об'єкт із семантикою Delphi; на мільйоні дрібних задач (bench06) він коштує ~1,2 мкс на задачу.
- **Стан:** модуль `System.Threading.ForkJoin` (пакет `vcl-compat`): `TTaskGroup` (`Spawn` у трьох формах, `Wait`, `Cancel`), `TForkJoin.Each`, `TForkJoin.Join`. Задачі — записи без керованих полів у деках Чейза–Лева з крадіжкою роботи, `Wait` сам виконує задачі. bench06: ~80–90 мс проти ~1250 мс через `TTask`. Рішення — [adr/0013-forkjoin-fine-grained-tasks.md](adr/0013-forkjoin-fine-grained-tasks.md), посібник — [guides/forkjoin.md](guides/forkjoin.md), приклад — `examples/forkjoin.pp`, тести — `packages/vcl-compat/tests/utforkjoin.pp`.

## 2. Синтаксична ергономіка мови (рівень компілятора `compiler/`)

У реальному багатопоточному й узагальненому коді Free Pascal поступається лаконічністю через надмірні синтаксичні вимоги режиму `objfpc`.

### 2.1. Виведення типів для узагальнених методів (Generic Type Inference) та необов'язковий `specialize` [РЕАЛІЗОВАНО]
- **Було**:
  ```pascal
  R := TTask.specialize Future<string>(function: string begin Result := 'ok'; end);
  ```
- **Реалізовано**:
  1. За перемикачем `{$modeswitch implicitgenerics}` дозволено опускати ключове слово `specialize` у режимі `objfpc` для типів (`IFuture<string>`, `TFPGList<Integer>`) та явних викликів методів і функцій (`Identity<string>('hello')`, `TTask.Future<string>(...)`).
  2. Реалізовано автоматичне виведення типового параметра `<T>` (Generic Type Inference) з типів переданих аргументів, зокрема з типу повернення та параметрів анонімних функцій і посилань на функції (`reference to function/procedure`):
     ```pascal
     {$mode objfpc}{$H+}
     {$modeswitch implicitgenerics}
     {$modeswitch anonymousfunctions}
     {$modeswitch functionreferences}

     // Автоматичне виведення T = string -> IFuture<string>:
     R := TTask.Future(function: string begin Result := 'ok'; end);

     // Автоматичне виведення в неблокувальних ланцюжках ThenBy:
     Next := R.ThenBy(function(const Prev: ITask): Integer begin Result := Length(IFuture<string>(Prev).Value); end);
     ```
  3. Повний набір тестів додано до `tests/concurrency/test_implicit_generics.pp`.
  4. Розширене виведення працює лише з `{$modeswitch implicitgenerics}`; штатний `implicitfunctionspecialization` поводиться як у FPC (тест upstream `timpfuncspez15`, тести форку `timplgen1`/`timplgen2`). Посібник — [language/implicit-generics.md](language/implicit-generics.md).

### 2.2. Короткий синтаксис лямбда-виразів (`=>`) [РЕАЛІЗОВАНО]
- **Статус**: Повністю реалізовано в компіляторі (`{$modeswitch arrowfunctions}`) разом із контекстним виведенням типів параметрів і результату.
- **Синтаксис**:
  ```pascal
  {$modeswitch arrowfunctions}
  {$modeswitch implicitgenerics}

  // Паралельний цикл (з дужками або без дужок для 1 аргументу):
  TParallel.&For(0, N - 1, (I) => Results[I] := Work(I));
  TParallel.&For(0, N - 1, I => Results[I] := Work(I));

  // Безпараметричні лямбди та Generic Type Inference:
  R := TTask.Future(() => ComputeResult(42));

  // Лямбди з кількома аргументами та операціями над рядками / керованими типами:
  ConcatOp := (Count, Msg) => Msg + ': ' + IntToStr(Count);

  // Блоки з кількома інструкціями:
  LogAndWork := (I) => begin Log(I); Work(I); end;
  ```
- **Документація та тести**:
  - Детальний посібник: [`guide-arrow-functions.md`](guide-arrow-functions.md).
  - Тестовий набір: [`tests/concurrency/test_arrow_functions.pp`](../../tests/concurrency/test_arrow_functions.pp).

### 2.3. Оголошення локальних змінних за місцем використання (`inlinevars`) [РЕАЛІЗОВАНО]
- За опціональним `{$modeswitch inlinevars}` (сумісно з Delphi 10.3+) дозволено:
  ```pascal
  var Fastest := TTask.WaitForAny([R0, R1, R2], 1000);
  for var E in Agg do
    WriteLn(E.Message);
  ```
  Особливо корисно для складних спеціалізацій дженериків та змінних-лічильників циклів, де область видимості обмежується самим циклом.

**Стан:** `var X := Expr;`, `var X: T := Expr;`, `var A, B: T;`, `for var I := ... to/downto`, `for var E in ...` (тип елемента масиву, рядка, множини, переліку, нумератора). Тип виводиться з ініціалізації (цілі константи — `Integer`/`Int64`, рядкові — рядковий тип режиму) і далі статичний. Видимість — до кінця списку операторів (`begin..end`, `repeat..until`, частини `try`), `for var` — лише в циклі; повтор імені в сусідніх блоках дозволений. Змінна живе в кадрі підпрограми (керовані типи фіналізуються на виході з неї). Без перемикача компілятор поводиться як FPC. Посібник — [language/inline-vars.md](language/inline-vars.md), приклад — `examples/inline_vars.pp`, тести — `tests/test/tinlinevar1`–`24`.

### 2.4. Кортежі (Tuples) та деконструкція `(A, B) := Func()` [РЕАЛІЗОВАНО]
- **Статус**: Повністю реалізовано в компіляторі (`{$modeswitch tuples}`).
- **Синтаксис та можливості**:
  ```pascal
  {$mode objfpc}{$H+}
  {$modeswitch tuples}

  // 1. Позиційні та іменовані типи кортежів:
  function DivRem(A, B: Integer): (Integer, Integer);
  function CountAndSumPrimes(Limit: Integer): (Count: Integer, Sum: Int64);

  // 2. Літерали кортежів:
  Result := (Integer(A div B), Integer(A mod B));
  NamedTup := (42, 9999999999);

  // 3. Деконструкція в наявні змінні або з оголошенням локальних змінних:
  (Q, R) := DivRem(10, 3);
  var (Count, Sum) := CountAndSumPrimes(5000000);
  var (Greeting, Answer) := ('Hello', 42);

  // 4. Одночасний обмін значеннями без тимчасової змінної (Swap):
  (X, Y) := (Y, X);
  (A, B, C) := (C, A, B);
  (S1, S2) := (S2, S1); // Повна безпека для рядків та керованих типів

  // 5. Доступ до полів: іменований та позиційний фолбек:
  Writeln(NamedTup.Count); // 42
  Writeln(NamedTup.Item1); // 42 (позиційний псевдонім)

  // 6. Структурна еквівалентність між типами кортежів:
  var T1: (X: Integer, Y: Integer);
  var T2: (Integer, Integer);
  T2 := T1; // Сумісні за структурою
  ```
- **Документація та тести**:
  - Детальний посібник: [`guide-tuples.md`](guide-tuples.md).
  - Тестовий набір: [`tests/concurrency/test_tuples.pp`](../../tests/concurrency/test_tuples.pp).

### 2.5. Оператор ресурсу `using .. do` (`{$modeswitch using}`) [РЕАЛІЗОВАНО]
- Пропозиція 4.2 з `proposals/modern_pascal_productivity_and_web_vision.md`: прибрати шаблон `try .. finally X.Free; end;` для локальних тимчасових об'єктів.
  ```pascal
  using var Src := TFileStream.Create(A, fmOpenRead),
        var Dst := TFileStream.Create(B, fmCreate) do
    Dst.CopyFrom(Src, 0);   // Dst, потім Src звільняються навіть після винятку
  ```

**Стан:** `using var X[: T] := Expr do S` (нова змінна, видима лише в операторі) і `using X := Expr do S` (змінна з секції `var`, після оператора `nil`); кілька ресурсів через кому, звільнення у зворотному порядку, також після винятку, `Exit`, `Break`, `Continue` і невдалої ініціалізації наступного ресурсу. Клас звільняється `TObject.Free`, COM-інтерфейс — присвоєнням `nil`; інші типи — помилка компіляції. Присвоєння ресурсу в операторі — помилка компіляції (як для змінної циклу). Компілюється в той самий `try..finally`, без додаткових витрат. `using` — зарезервоване слово лише з перемикачем. Посібник — [language/using.md](language/using.md), приклад — `examples/using_resources.pp`, тести — `tests/test/tusing1`–`20`.

### 2.6. Інтерполяція рядків `$'...'` (`{$modeswitch interpolation}`) [РЕАЛІЗОВАНО]
- Пропозиція 4.3 з `proposals/modern_pascal_productivity_and_web_vision.md`: замість `Format('%s %d', [...])`, де помилку типу видно лише в рантаймі, — рядок із виразами, які перевіряє компілятор.
  ```pascal
  WriteLn($'Замовлення #{Order.Id} від {Order.Customer}: {Order.Total:0:2} грн');
  ```

**Стан:** `$'текст {Вираз} {Вираз:Ширина} {Вираз:Ширина:Точність}'`, `{{`/`}}` для дужок, `''` для апострофа, рядкові константи й виклики функцій у виразах, вкладені `$'...'`; багаторядкові `` $`...` `` (з `multilinestrings`, кінці рядків за `$MULTILINESTRINGLINEENDING`). Форматування — як у `WriteStr`/`WriteLn` (класи, записи, вказівники — помилка компіляції). Рядки й символи без специфікаторів конкатенуються, інакше — `WriteStr` у тимчасовий рядок; результат — рядковий тип режиму, без виразів — рядкова константа. Розбору шаблону під час виконання немає: удвічі швидше за `Format`, з рядками — на порядок. `$FF` не змінюється. Посібник — [language/interpolation.md](language/interpolation.md), приклад — `examples/interpolation.pp`, тести — `tests/test/tinterp1`–`20`.

### 2.7. Методи для стандартних типів (`{$modeswitch extensionmethods}`) [РЕАЛІЗОВАНО]
- Пропозиція 4.7 з `proposals/modern_pascal_productivity_and_web_vision.md`: методи для `string`, `Integer`, `TDateTime` тощо. У FPC це вже є як помічники типів (`type helper for Integer`), тож нового синтаксису не потрібно; заважала пастка: власний помічник ховає `TStringHelper` з SysUtils.

**Стан:** перемикач форку `{$modeswitch extensionmethods}` вмикає `typehelpers` і `multihelpers` разом (`extensionmethods-` вимикає обидва): власні помічники для рядків, чисел, `TDateTime`, переліків, масивів і записів співіснують із помічниками SysUtils та інших модулів незалежно від порядку `uses`. Наявні `typehelpers`/`multihelpers` поводяться як в upstream. Посібник — [language/helpers.md](language/helpers.md) (правила вибору методу, пастки: точний тип, імена всередині помічника, `5.ToString`, відсутність узагальнених помічників), приклад — `examples/extension_methods.pp`, тести — `tests/test/textmeth1`–`6`. Узагальнені помічники (`helper for TArray<T>`) — не реалізовано.

---

## 3. Пам'ять, безпека та нульові накладні витрати (рівень Rust / C++20)

### 3.1. Розумні вказівники на базі керованих записів (`TScoped<T>`, `TArc<T>`) у RTL [РЕАЛІЗОВАНО]
Механізм Management Operators (`Initialize`, `Finalize`, `AddRef`, `Copy`) для `advancedrecords` у FPC вже дозволяє створити стандартний модуль `sysmanaged` / `smartptrs`:
- **`TScoped<T>` (аналог `std::unique_ptr`)** — автоматично викликає `.Free` при виході зі стекового кадру (навіть у разі винятку), усуваючи потребу в `try..finally` для локальних об'єктів (`TStringList`, `TMemoryStream`, `TThreadPool`).
- **`TArc<T>` (Atomic Reference Counted)** — потокобезпечне спільне володіння для будь-якого класу `TObject` без вимоги успадковувати `TInterfacedObject`.

**Стан:** модуль `smartptrs` / `System.SmartPtrs` у `packages/rtl-objpas`; додатково `TWeak<T>` (аналог `std::weak_ptr`) для розриву циклів. Посібник — [guides/smart-pointers.md](guides/smart-pointers.md), рішення — [ADR-0007](adr/0007-smart-pointers.md), приклад — `examples/smart_pointers.pp`, тести — `packages/rtl-objpas/tests/utcsmartptrs.pp`. Фабрики з виведенням типу `MakeScoped(X)`/`MakeArc(X)` — після виправлення в компіляторі перевірки обмежень у заголовку реалізації обмежених дженериків (`FPC_HAS_CONSTRAINED_GENERIC_FORWARD`, тести `tests/test/tgenconstraint41`–`58`). Некопійовані типи `end nocopy;` ([ADR-0008](adr/0008-nocopy-types.md)) [РЕАЛІЗОВАНО]: `TScoped<T>` і гарди `SyncObjs` відхиляють копії під час компіляції (`FPC_HAS_NOCOPY_TYPES`, тести `tests/test/tnocopy*`).

### 3.2. Безпечні зрізи пам'яті (`TSpan<T>` / `TReadOnlySpan<T>`) [РЕАЛІЗОВАНО]
- Легковагова структура `(Ptr: ^T; Length: SizeInt)` з перевіркою меж (при `-Cr`), що представляє неперервний піддіапазон статичного масиву, динамічного масиву, рядка або `TBytes` без копіювання і без алокацій у купі.
- Дозволяє безпечно передавати неперетинні сегменти масиву в паралельні задачі `System.Threading`.

**Стан:** модуль `spans` / `System.Spans` у `packages/rtl-objpas`: `Slice`, `Chunk` (неперетинне розбиття для паралельних задач), `CopyFrom` з перекриттям, `SpanOf`/`MutableSpanOf` для рядків. Межі перевіряються **завжди**, а не лише при `-Cr`: код дженерика компілюється з налаштуваннями модуля, де його оголошено, тож `-Cr` користувача на нього не діє ([ADR-0009](adr/0009-spans.md)). Посібник — [guides/spans.md](guides/spans.md), приклад — `examples/spans_parallel.pp`, тести — `packages/rtl-objpas/tests/utcspans.pp`.

### 3.3. Підтримка ThreadSanitizer (`-fsanitize=thread`) та AddressSanitizer (`-fsanitize=address`) у генераторі коду [TSan і ASan x86_64-linux РЕАЛІЗОВАНО]
- Доповнення модуля `fpvalgrind` вбудованою інструментацією читань/записів пам'яті в компіляторі для TSan та ASan:
  - у 5–10 разів менше сповільнення порівняно з Valgrind Helgrind;
  - цільова платформа — x86_64-linux ([ADR-0011](adr/0011-target-platform.md)).

**Стан:** ключ `-fsanitize=thread` для x86_64-linux (рідний генератор коду): прохід `compiler/x86/saninstr.pas` інструментує остаточні інструкції з операндом-пам'яттю (точний розмір доступу, без кадру процедури, `threadvar` і атомарних інструкцій), трампліни й лінкування `libtsan` — модуль `fpctsan` (`rtl-objpas`), `cthreads` під TSan викликає pthread через перехоплювачі, `TArc<T>` анотовано `TsanRelease`/`TsanAcquire`. Сповільнення стрес-тестів `smartptrs` — 2–3× (Helgrind — ~1300×). Рішення — [ADR-0010](adr/0010-tsan.md), посібник — [guides/tsan.md](guides/tsan.md), тести — `tests/concurrency/run-tsan.sh`, `tests/test/ttsan1`–`5`.

**ASan:** ключ `-fsanitize=address` (x86_64-linux): той самий прохід із трамплінами `fpcasan` (швидка перевірка тіньової пам'яті в трампліні, звіт «з місця доступу»), `cmem` + `libasan`, кадр `rbp` у всьому інструментованому коді. Знаходить переповнення купи, use-after-free, подвійне звільнення, витоки (LeakSanitizer); стек і глобальні змінні не перевіряються. Сповільнення тестів `smartptrs` — 2,2×. Рішення — [ADR-0012](adr/0012-asan.md), посібник — [guides/asan.md](guides/asan.md), тести — `tests/concurrency/run-asan.sh`, `tests/test/tasan1`–`3`. Далі: повні стеки TSan (`__tsan_func_entry/exit`); червоні зони стеку й глобальних змінних для ASan.

---

## 4. Інструментарій та екосистема

1. **Єдиний CLI-інструмент збірки, залежностей і тестування (`fpc pkg`)**:
   - Декларативний маніфест проєкту (альтернатива складним `Makefile.fpc` і ручним `-Fu`/`-Fi`), запуск модульних і стрес-тестів однією командою (`fpc test`), профілювання та перевірка під Valgrind/Sanitizer.
2. **Офіційний Language Server (LSP) на базі фронтенду компілятора**:
   - Повна підтримка `generic`/`specialize`, анонімних функцій, макросів та умовних директив у сучасних IDE та редакторах.

---

## 5. Пріоритети впровадження у гілці `feature/concurrency`

| Пріоритет | Напрямок | Де реалізується | Складність | Очікуваний ефект |
|---|---|---|---|---|
| **1** | `TChannel<T>`, `TCountdownEvent`, `TBarrier`, `TCancellationToken`, `.ContinueWith` [РЕАЛІЗОВАНО] | `packages/fcl-base`, `packages/vcl-compat` | Середня | Повноцінна оркестрація потоків і передавання повідомлень без низькорівневих блокувань |
| **2** | Розумні вказівники `TScoped<T>` / `TArc<T>` та `TSpan<T>` [РЕАЛІЗОВАНО] | `packages/rtl-objpas` | Низька–середня | Зникнення шаблонних блоків `try..finally` і витоків пам'яті в багатопоточному коді |
| **3** | Необов'язковий `specialize` + виведення типів для дженериків [РЕАЛІЗОВАНО] | `compiler/` (`pexpr.pas`, `ptype.pas`, `pgenutil.pas`) | Середня | Суттєве очищення синтаксису `TTask.Future`, колекцій та алгоритмів |
| **4** | Асинхронний цикл подій `fcl-eventloop` (`epoll`/`io_uring`) [РЕАЛІЗОВАНО] | `packages/fcl-eventloop` | Висока | Високопродуктивні мережеві сервіси на FPC |
| **5** | Короткі лямбди `=>` та `async`/`await` [РЕАЛІЗОВАНО] | `compiler/`, `packages/fcl-coroutines` | Висока | Рівень ергономіки сучасних C# / Rust / TypeScript при збереженні нативної швидкості FPC |

