# Посібник користувача: Корутини, Файбери та async / await (Фаза 1.4)

Цей посібник документує нововведення **Фази 1.4** у гілці `feature/concurrency`:
1. **Крок 1 (Бібліотечний)**: легковагові корутини/файбери (`TFiber`), генератори (`TGenerator<T>`) та будівельники скінченних автоматів (`TTaskCompletionSource<T>`, `TAsyncTaskMethodBuilder<T>`) у новому пакеті `packages/fcl-coroutines/`.
2. **Крок 2 (Компіляторний)**: синтаксичний модифікатор/директива `async` для процедур та функцій, що повертають `ITask` або `specialize IFuture<T>`, та оператор `await` для трансформації очікування результату в неблокувальне виконання.

---

## 1. Архітектурний огляд

```
+-------------------------------------------------------------------------------+
|                        Користувацький код (User Code)                         |
|   procedure Worker; async;        |   Val := await Future;   |   await Task;  |
+-----------------------------------+--------------------------+----------------+
                                    |
+-----------------------------------+-------------------------------------------+
|               Компілятор FPC Trunk (compiler/ppcx64)                          |
|   - pio_async у timplprocoption   |   - Контекстний оператор await            |
|   - Директива async для методів   |   - Автоматичний розгорт .Value / .Wait   |
+-----------------------------------+-------------------------------------------+
                                    |
+-----------------------------------+-------------------------------------------+
|                   Пакет fcl-coroutines (packages/fcl-coroutines/)                    |
|   - TFiber (стекові корутини)     |   - TGenerator<T> (for..in генератори)    |
|   - TFiber.Await<T> / Sleep       |   - TTaskCompletionSource<T> (стейт-машини)|
+-----------------------------------+-------------------------------------------+
                  |                                           |
+-----------------+-------------------+   +-------------------+-----------------+
|      fcl-eventloop (Фаза 1.3)       |   |       System.Threading (Фаза 1.1)   |
|   - epoll / io_uring / kqueue / IOCP|   |   - ITask, IFuture<T>, TThreadPool  |
|   - Min-Heap високоточні таймери    |   |   - TCancellationToken, ThenBy      |
+-------------------------------------+   +-------------------------------------+
```

---

## 2. Бібліотечні корутини (Файбери: `TFiber`)

Модуль `async.fiber.pp` реалізує легковагові стекові корутини (User-Space Fibers), які дозволяють виконувати асинхронний код у звичному послідовному стилі:

### 2.1. Особливості реалізації:
- **Швидке перемикання контексту**: власна асемблерна реалізація `FiberSwitchContext` для System V AMD64 ABI, що зберігає та відновлює лише callee-saved регістри (`%rbx, %rbp, %r12-%r15`) та покажчик стеку `%rsp` за менш ніж 10 наносекунд.
- **Вирівнювання стеку по ABI**: стек файбера гарантовано ініціалізується з 16-байтним вирівнюванням (`%rsp % 16 == 8` на вході в функцію), що запобігає збоям векторних інструкцій SSE/AVX (`movaps`).
- **Ізоляція стеку винятків FPC**: Free Pascal використовує глобальні threadvar змінні `ExceptAddrStack` та `ExceptObjectStack` для обробки `try..except` та `try..finally`. `TFiber` динамічно отримує зміщення цих змінних через механізм `FPC_THREADVAR_RELOCATE` та зберігає/відновлює окремий ланцюг обробників винятків для кожного файбера.
- **Безпечна міграція між системними потоками ОС**: адреси `ExceptAddrStack` повторно обчислюються після повернення у контекст, що дозволяє файберу, який призупинився на одному системному потоці (наприклад, головному потоці), бути безпечно відновленим на іншому (наприклад, у пулі робочих потоків чи в потоці реактора EventLoop).

### 2.2. Приклад використання TFiber:
```pascal
program FiberExample;
{$mode objfpc}{$H+}
uses
  cthreads, SysUtils, System.Threading, fcleventloop, fclasync;

type
  TWorker = class
    Loop: IEventLoop;
    procedure Run;
  end;

procedure TWorker.Run;
var
  Fut: specialize IFuture<Integer>;
  Res: Integer;
begin
  WriteLn('Файбер розпочав роботу');

  { Запускаємо важке обчислення у пулі потоків }
  Fut := TTask.specialize Future<Integer>(
    function: Integer
    begin
      Sleep(100);
      Result := 42;
    end);

  { Неблокуюче призупинення файбера до готовності Future:
    потік ОС звільняється для інших задач }
  Res := TFiber.specialize Await<Integer>(Fut);
  WriteLn('Отримано результат з Future: ', Res);

  { Неблокуючий сон через таймер EventLoop }
  WriteLn('Засинаємо на 50 мс...');
  TFiber.Sleep(50, Loop);
  WriteLn('Прокинулись та завершуємо файбер');
end;

var
  Worker: TWorker;
  Fiber: TFiber;
begin
  Worker := TWorker.Create;
  try
    Worker.Loop := TEventLoop.Create(bkAuto);
    Fiber := TFiber.Create(@Worker.Run, 128 * 1024, Worker.Loop);
    try
      Fiber.Resume;

      { Прокручуємо цикл подій для таймерів та I/O }
      while Fiber.State in [fsSuspended, fsRunning] do
        Worker.Loop.RunOnce(10);
    finally
      Fiber.Free;
    end;
  finally
    Worker.Free;
  end;
end.
```

---

## 3. Генератори послідовностей (`TGenerator<T>`)

Модуль `async.generator.pp` надає generic-клас `TGenerator<T>`, що дозволяє створювати ледачі (lazy) послідовності на базі корутин, з прямою підтримкою циклів `for..in`:

```pascal
program GeneratorExample;
{$mode objfpc}{$H+}
uses
  SysUtils, async.generator;

type
  TIntGen = specialize TGenerator<Integer>;

procedure FibonacciProducer(const Yield: TIntGen.TYieldProc);
var
  A, B, Temp, I: Integer;
begin
  A := 0;
  B := 1;
  for I := 1 to 10 do
  begin
    Yield(B); // Призупиняє генератор та повертає значення
    Temp := A + B;
    A := B;
    B := Temp;
  end;
end;

var
  Gen: TIntGen;
  Val: Integer;
begin
  Gen := TIntGen.Create(@FibonacciProducer);
  try
    { Ледачий обхід у циклі for..in }
    for Val in Gen do
      Write(Val, ' ');
    WriteLn;
  finally
    Gen.Free;
  end;
end.
```

---

## 4. Стейт-машини: `TTaskCompletionSource<T>`

Модуль `async.statemachine.pp` надає фундаментальні примітиви C# Roslyn-патерну для створення обіцянок (promises) та керування асинхронним станом:

```pascal
var
  Tcs: specialize TTaskCompletionSource<string>;
  Fut: specialize IFuture<string>;
begin
  Tcs := specialize TTaskCompletionSource<string>.Create;
  try
    Fut := Tcs.Task; // Отримуємо IFuture<string>

    TTask.Run(
      procedure
      begin
        Sleep(50);
        Tcs.SetResult('Успіх!'); // Пробуджує всі продовження та очікування
      end);

    WriteLn(Fut.Value); // Виведе 'Успіх!'
  finally
    Tcs.Free;
  end;
end;
```

---

## 5. `async` та `await`: уніфікований синтаксис та дві моделі виконання

Типовим режимом компілятора за замовчуванням є **`{$ASYNCMODE AUTO}`**, тобто **файберний режим** (`FIBER`). Автоматний режим (`STATEMACHINE`) вмикається виключно явно відповідною директивою.

Один режим **не є «суворішим варіантом» іншого**. Під єдиним спільним синтаксисом ховаються два різні архітектурні сенси `Result` і два різні сенси очікування:
1. **У файберному режимі (`FIBER` / `AUTO`, типовий)**:
   - **Сенс `Result`**: `Result: T` — це результат повернення замикання на справжньому виділеному стеку файбера (128 КБ), який після завершення корутини публікується в `IFuture<T>`.
   - **Сенс `await`**: це кооперативне перемикання контексту процесора (стек файбера лишається живим у пам'яті, регістри CPU зберігаються, потік ОС звільняється).
   - Компілятор фазою `lower_async_fiber` автоматично огортає тіло у `TFiber.Async<T>` (або `TFiber.Spawn`), гарантуючи, що код завжди виконується у файбері, а `TaskAwaitHook` перехоплює очікування без блокування потоку.
2. **У режимі автомата (`STATEMACHINE`)**:
   - **Сенс `Result`**: `Result: T` — це внутрішнє поле стану автомата (`$ASYNCRESULT`), що зберігається на купі в об'єкті-захоплювачі між переходами станів.
   - **Сенс `await`**: це розрізання тіла на кроки (безстекова підписка на continuation), де кадр стека знищується на кожній паузі.

Для розробника код виглядає однаково:
- Розробник пише однаковий код незалежно від директиви режиму.
- Усередині функції `function ...: specialize IFuture<T>; async;` змінна `Result` завжди має тип внутрішнього значення `T` (а не `IFuture<T>`).
- Виклик `await` не блокує потік ядра в обох режимах.

### 5.1. Оператор `await`

`await` дозволений лише в підпрограмі, оголошеній з `async`. Інакше це
помилка компіляції `parser_e_await_only_in_async` (03381): стрілка без
префікса `async`, звичайна процедура і головна програма. Зовнішня
`async`-підпрограма цього не скасовує.

Завдяки фазі `lower_async_fiber` тіло функції `async` у файберному режимі **гарантовано виконується у контексті файбера**, тому `await E` (який транслюється у `E.Value` або `E.Wait`) перехоплюється встановленим `TaskAwaitHook` і призупиняє файбер, вивільняючи потік ОС для інших задач.

| Режим та контекст `await` | Що відбувається |
|---|---|
| `async`-функція або процедура (`{$ASYNCMODE FIBER}`) | компілятор загортає тіло у файбер; `await` не блокує OS-потік, файбер призупиняється і відновлюється після завершення задачі |
| `async`-функція або процедура (`{$ASYNCMODE STATEMACHINE}`) | компілятор розрізає тіло на стани; `await` призупиняє крок стейт-машини без блокування потоку |
| у генераторі (`TGenerator<T>`) | очікування **блокує** потік: файбер генератора перемикається лише в `Yield` |
| поза `async` | помилка компіляції 03381 (не блокуючий `Wait`) |

`await` — контекстне ключове слово: якщо в області видимості є змінна,
функція чи поле з іменем `await`, воно має звичайне значення.

### 5.2. `TFiber.Async` і `TFiber.Spawn`: бібліотечний запуск

Для ручного запуску корутин поза синтаксисом `async;` (наприклад, для анонімних функцій чи запуску на явному `IEventLoop`) використовуються методи:

```pascal
uses SysUtils, System.Threading, fcleventloop, async.fiber;

var
  Loop: IEventLoop;
  Total: specialize IFuture<Integer>;
begin
  Loop := TEventLoop.Create(bkAuto);
  Total := TFiber.specialize Async<Integer>(
    function: Integer
    var
      A, B: Integer;
    begin
      A := DownloadSizeAsync('a.bin').Value;  // файбер чекає, потік вільний
      B := DownloadSizeAsync('b.bin').Value;
      Result := A + B;
    end, Loop);
  while Total.Status <> TTaskStatus.Completed do
    Loop.RunOnce(10);
  WriteLn(Total.Value);
end.
```

`Async` виконує функцію синхронно до першого очікування незавершеної задачі
і тоді повертає майбутнє — як `async`-метод у C#. З `Loop` уся корутина
виконується в потоці циклу (тисяча корутин можуть чекати на одному потоці);
без `Loop` вона продовжується в потоках пулу. `Spawn` — те саме для процедури,
повертає `ITask`. Виняток корутини потрапляє в її майбутнє. Файбер
звільняється сам, коли функція повертає результат.

### 5.3. Директива `async` та компіляторна валідація

Компілятор FPC (`compiler/pdecsub.pas`) здійснює строгу типізаційну перевірку підпрограм із модифікатором `async;`:
- **Функції**: тип повернення зобов'язаний бути асинхронним типом — інтерфейсом (`specialize IFuture<T>`, `ITask`), класом або асинхронним дескриптором. Спроба оголосити `function Bad: Integer; async;` призводить до помилки компіляції:
  ```text
  Error: Async function must return ITask or IFuture<T>
  ```
- **Процедури**: `procedure Worker; async;` трактуються як асинхронні fire-and-forget операції.
  - **Оптимізація без `await`**: якщо процедура з `async;` не містить жодного оператора `await`, компілятор в обох режимах (`FIBER` і `STATEMACHINE`) не виділяє файбер чи структуру автомата, а виконує її як звичайну синхронну процедуру з нульовим оверхедом.

### 5.4. Чистий асинхронний синтаксис (без ручних обгорток `RunAsync`)

Завдяки уніфікованій фазі `lower_async_fiber` розробнику більше **не потрібно** писати ручні обгортки на зразок `Result := RunAsync(...)`. Код функції пишеться максимально природно:

```pascal
function ComputeAsync(X: Integer): specialize IFuture<Integer>; async;
var
  A, B: Integer;
begin
  // В ОБОХ режимах Result має тип Integer (T), а await є неблокуючим!
  A := await FetchPartA(X);
  B := await FetchPartB(X);
  Result := A + B;
end;
```

- Під капотом для режиму `FIBER` компілятор автоматично перетворює цей код на виклик `Result := TFiber.Async<Integer>(...)`.
- Перемикання директиви між `{$ASYNCMODE STATEMACHINE}` та `{$ASYNCMODE FIBER}` вимагає **нуль змін** у тілі функцій.
- Прямі хелпери `RunAsync<T>(Func)` та `SpawnAsync(Proc)` у модулі `fclasync` залишаються доступними для випадків, коли потрібно запустити асинхронну лямбду з коду, який сам не є `async`-підпрограмою.

---

## 6. Збірка та запуск тестів

Для перевірки роботи функціоналу асинхронності:
```sh
# Збірка і запуск комплексного тесту сучасного async/await (по аналогії з C#/Rust/Go):
. tests/concurrency/fpcenv.sh
$FPC_TRUNK @"$FPC_CFG" -Fupackages/fcl-coroutines/src tests/concurrency/test_modern_async.pp
./tests/concurrency/test_modern_async

# Збірка і прогін модульних тестів fcl-coroutines (28 тестів):
./tests/concurrency/build-async.sh
./tests/concurrency/out-async/testasync -a --format=plain

# Збірка і прогін демонстраційного прикладу coroutine_showcase:
$FPC_TRUNK @"$FPC_CFG" -FE./tests/concurrency/out-async -FU./tests/concurrency/out-async \
  -Fi./packages/fcl-coroutines/src -Fu./packages/fcl-coroutines/src -Fu./packages/fcl-coroutines/tests \
  docs/concurrency/examples/coroutine_showcase.pp
./tests/concurrency/out-async/coroutine_showcase
```

