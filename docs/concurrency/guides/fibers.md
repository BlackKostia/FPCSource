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

## 5. `async` та `await`: що вони роблять насправді

Цей розділ описує типовий режим `{$ASYNCMODE AUTO}` і `{$ASYNCMODE FIBER}`:
`await` лишається очікуванням файбера. `{$ASYNCMODE STATEMACHINE}` знижує
тіло до автомата на купі і не викликає `Wait`. Його семантика `Result`,
дозволені конструкції і `TTask.Delay` — у [statemachine.md](statemachine.md).

### 5.1. Оператор `await`

`await` дозволений лише в підпрограмі, оголошеній з `async`. Інакше це
помилка компіляції `parser_e_await_only_in_async` (03381): стрілка без
префікса `async`, звичайна процедура і головна програма. Зовнішня
`async`-підпрограма цього не скасовує.

У `{$ASYNCMODE AUTO}` і `FIBER` дозволений `await E` компілятор перетворює
на `E.Value`, якщо `E` має член `Value` (`IFuture<T>`), інакше на `E.Wait`
(`ITask`). Чи блокує це потік, залежить від того, де виконується код:

| Де виконується `await` в `async`-підпрограмі | Що відбувається |
|---|---|
| усередині файбера (`TFiber.Async`, `TFiber.Spawn`, власний `TFiber`) | файбер **призупиняється**, потік ОС вільний; файбер продовжить роботу, коли задача завершиться — у потоці свого циклу подій або, без циклу, у потоці пулу |
| у генераторі (`TGenerator<T>`) | очікування **блокує** потік: файбер генератора перемикається лише в `Yield` |
| поза файбером | очікування **блокує** поточний потік, як `Value`/`Wait` |

Зворотний виклик `TFiber.Async`, `RunAsync` чи `SpawnAsync` сам часто не
позначений `async` (він повертає внутрішнє `T`, а не `IFuture<T>`). У ньому
`await` — помилка. Пишіть `.Value` або `.Wait`: вони так само віддають
файбер через `TaskAwaitHook`. Так само неблокувально всередині файбера
працюють `IFuture.Value`, `ITask.Wait` без таймауту і `TTask.WaitForAll`
без таймауту. `Wait` з таймаутом і `WaitForAny` блокують і у файбері.

`await` — контекстне ключове слово: якщо в області видимості є змінна,
функція чи поле з іменем `await`, воно має звичайне значення.

### 5.2. `TFiber.Async` і `TFiber.Spawn`: асинхронний код без зворотних викликів

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

### 5.4. Ергономічний синтаксис `RunAsync` та `SpawnAsync` (модуль `fclasync`)

Для найбільш зручного написання асинхронного коду в стилі сучасних мов програмування модуль `fclasync` надає прямі хелпери:
- **`RunAsync<T>(Func)`** — виконує функцію як асинхронну корутину і миттєво повертає викликачу `specialize IFuture<T>`.
- **`SpawnAsync(Proc)`** — запускає процедуру у фоновій корутині, повертаючи `ITask`.
- **`AsyncSleep(ms)`** — неблокуючий сон у файбері, що вивільняє системний потік.

Приклад з повною підтримкою лямбд `=>`:
```pascal
function CalculateDataAsync(Id: Integer): specialize IFuture<Integer>; async;
begin
  Result := specialize RunAsync<Integer>(
    function: Integer
    var
      DataA, DataB: Integer;
    begin
      // Неблокуюче призупинення файбера на .Value:
      DataA := FetchPartAAsync(Id).Value;
      DataB := FetchPartBAsync(Id).Value;
      Result := DataA + DataB;
    end);
end;

// Виклик з боку викликача НЕ блокує потік:
F := CalculateDataAsync(42); // повертає IFuture миттєво (< 1 мс)
// Виконуємо іншу роботу...
Total := F.Value; // розгортає результат
```

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

