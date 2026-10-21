# Посібник: `async` / `await` як автомат (`{$ASYNCMODE STATEMACHINE}`)

Директива `{$ASYNCMODE}` обирає, чим стає `await` у процедурі з `async`.
Приклад — [`examples/statemachine.pp`](../examples/statemachine.pp),
тести — `tests/concurrency/test_statemachine_async.pp`, порівняння з C# —
`tests/concurrency/sm-compare`. Файберний шлях
(`AUTO` і `FIBER`) описаний у [fibers.md](fibers.md).

## 1. Два режими

| `{$ASYNCMODE}` | Що робить `await` |
|---|---|
| `AUTO` (типово) і `FIBER` | `await E` стає `E.Value` (`IFuture<T>`) або `E.Wait` (`ITask`). Усередині файбера це віддає потік через `TaskAwaitHook`. Поза файбером потік блокується. Код із `Result := RunAsync(...)` лишається чинним. |
| `STATEMACHINE` | Тіло процедури з `async` компілятор знижує до автомата на купі. `await` призупиняє крок. Потік пулу не спить у `Wait`. |

Ім'я `await` лишається звичайним ідентифікатором, якщо в області видимості
вже є змінна, функція чи поле з таким ім'ям.

Потрібні `{$mode objfpc}`, `{$H+}` і `{$modeswitch functionreferences}`:
крок автомата — посилання на функцію, а локальні змінні, що живуть через
`await`, компілятор переносить на захоплювач у купі.

## 2. Виклик

```pascal
{$ASYNCMODE STATEMACHINE}

function Pipeline: specialize IFuture<Integer>; async;
var
  N: Integer;
begin
  N := 1;
  await TTask.Delay(200);
  Result := N + 41;
end;
```

`Pipeline` повертається одразу, ще до завершення затримки, і майбутнє ще
не завершене. Перший крок виконується в цьому ж виклику, доки не зустріне
незавершене `await`. Далі крок продовжує потік пулу. `Pipeline.Value`
дочекається і поверне 42.

Якщо очікувана задача вже завершена, крок не призупиняється і йде далі
в тому самому виклику.

## 3. `Result`

У `STATEMACHINE` для `function ...: specialize IFuture<T>; async` і
`Result`, і `Exit(значення)` означають внутрішній `T`. Сам
`IFuture<T>` збирає і повертає згенерований код. Функція без жодного
`await` теж обгортається, інакше присвоєння `Result` не мало б куди
покласти `T`.

Функція `ITask` і процедура знижуються лише коли в тілі є `await`.
Функція `ITask` повертає задачу автомата. Процедура запускає її і не
віддає викликачеві. Узагальнений шаблон (`generic`) компілятор не
знижує: знижується вже спеціалізована копія.

У `AUTO` і `FIBER` `Result` як і раніше є самим future, тож
`Result := RunAsync(...)` там лишається правильним записом.

## 4. Що можна писати

- прямий ряд операторів;
- `await Task;` і `X := await Future`;
- `if` / `else`, `while`, `repeat`, `for` .. `to` / `downto` — `await`
  у тілі, не в умові і не в межах `for`;
- `break`, `continue`, `exit`;
- `try` / `finally` і `try` / `except` без `on`.

`finally` виконується на справжньому виході (нормальний кінець, `exit`,
`break` / `continue` назовні, виняток), а не в мить призупинення.
Збій очікуваної задачі піднімається знову, тож `except` у тілі його
бачить. Керована змінна (рядок, інтерфейс) переживає `await`: вона лежить
у захоплювачі, а не в кадрі стеку, який уже зник.

Цикл без `await` і без `exit` компілятор не розбирає на стани: його
власні `break` і `continue` лишаються звичайними.

## 5. Що є помилкою, а не блокуючим `Wait`

Помилка `parser_e_await_unsupported` (03390):

- `await` в умові `if`, `while`, `repeat`;
- `await` у більшому виразі (`await A + await B`);
- `await` у межі `for` і цикл `for` .. `in`;
- `case`, у гілці якого є `await`;
- `on E:` разом із `await` у тому самому `try`.

Так зроблено навмисно: мовчазний `Wait` знову зайняв би потік пулу.

## 6. `TTask.Delay`

```pascal
class function TTask.Delay(aMilliseconds: Cardinal): ITask; static;
```

Одна спільна черга дедлайнів і один потік таймера. Завершення ставиться
в пул, тож потік пулу не викликає `Sleep`. `Delay(0)` завершується одразу,
в тому самому виклику. Повернена задача не має значення: її чекають через
`await`, не через `.Value`.

20 000 таких очікувань по 20 мс —
`tests/concurrency/comparison/pascal/bench03_c100k_tasks.pp`. Це не
файберний bench03 і в таймований набір не входить.

## 7. Збірка прикладу

```sh
. tests/concurrency/fpcenv.sh
"$FPC_TRUNK" @"$FPC_CFG" -FEtests/concurrency docs/concurrency/examples/statemachine.pp
tests/concurrency/statemachine
```
