# Посібник користувача: розумні вказівники `TScoped<T>`, `TArc<T>`, `TWeak<T>`

Модуль `smartptrs` (`System.SmartPtrs` у dotted-збірці), пакет `rtl-objpas`.
Розділ 3.1 дорожньої карти ([roadmap.md](../roadmap.md)).

## 1. Навіщо

Кожен локальний об'єкт у Pascal вимагає пари `Create` / `try..finally Free`:

```pascal
var
  L: TStringList;
  S: TMemoryStream;
begin
  L := TStringList.Create;
  try
    S := TMemoryStream.Create;
    try
      // робота
    finally
      S.Free;
    end;
  finally
    L.Free;
  end;
end;
```

А спільний об'єкт, який читають кілька потоків, доводиться або загортати
в інтерфейс (`TInterfacedObject` + `IXxx`), або вручну домовлятися, хто
й коли його звільняє.

Керовані записи (management operators `Initialize`, `Finalize`, `AddRef`,
`Copy`) дозволяють перекласти цю роботу на компілятор — так само, як він
уже керує рядками й динамічними масивами:

```pascal
uses smartptrs;
type
  TStringListScoped = specialize TScoped<TStringList>;
  TMemoryStreamScoped = specialize TScoped<TMemoryStream>;
var
  L: TStringListScoped;
  S: TMemoryStreamScoped;
begin
  L.Reset(TStringList.Create);
  S.Reset(TMemoryStream.Create);
  // робота; обидва об'єкти звільняються на виході, навіть після винятку
end;
```

| Тип | Аналог | Володіння | Вартість |
|---|---|---|---|
| `TScoped<T>` | `std::unique_ptr`, Rust `Box` | одноосібне | один вказівник, без алокацій і атомарних операцій |
| `TArc<T>` | `std::shared_ptr`, Rust `Arc` | спільне, атомарний лічильник | вказівник + блок керування (одна алокація на об'єкт), `lock`-інструкція на копію/звільнення |
| `TWeak<T>` | `std::weak_ptr`, Rust `Weak` | немає (спостерігач) | вказівник на той самий блок керування |

Параметр типу обмежено класами (`T: class`); підходить будь-який нащадок
`TObject`, успадковувати `TInterfacedObject` не потрібно.

## 2. `TScoped<T>` — одноосібне володіння

### API

| Член | Опис |
|---|---|
| `class function Create(AObj: T): TScoped` | Бере `AObj` у володіння. `S := TScoped.Create(X)` звільняє те, чим `S` володів раніше. |
| `generic function MakeScoped<T>(AObj: T): TScoped<T>` | Те саме з виведенням типу: `S := MakeScoped(TStringList.Create)` (див. розділ 6). |
| `procedure Reset(AObj: T = nil)` | Звільняє поточний об'єкт і бере `AObj` (`nil` — просто звільнити). Повторний `Reset` тим самим об'єктом нічого не робить. |
| `function Release: T` | Віддає об'єкт без звільнення; відповідальність переходить до викликача. |
| `function Move: TScoped` | Передає володіння: `B := A.Move` — `A` порожній, старий об'єкт `B` звільнено. |
| `procedure Swap(var Other: TScoped)` | Обмін об'єктами без звільнення. |
| `function IsAssigned: Boolean` | Чи є об'єкт. |
| `function Get: T`, `property Obj: T` | Доступ до об'єкта (без передачі володіння). |

### Семантика

- Порожній за замовчуванням (`Initialize` записує `nil`).
- `Free` викликається при фіналізації запису: вихід зі стекового кадру
  (зокрема під час розкручування винятку), знищення класу чи запису, що
  містить `TScoped` як поле, звільнення динамічного масиву.
- **Копіювати володіння не можна.** `TScoped<T>` оголошено `end nocopy;`
  (некопійований тип, [ADR-0008](../adr/0008-nocopy-types.md)), тому
  **компілятор** відхиляє (`Type "..." cannot be copied`):
  - присвоєння `B := A` зі змінної, поля, елемента, розіменування;
  - параметр за значенням (`procedure P(S: TScoped)`);
  - `Copy()` динамічного масиву `TScoped`, а також присвоєння запису чи
    статичного масиву, що містить `TScoped`.

  Копії, яких компілятор не бачить, перевіряються під час виконання
  (`AddRef`/`Copy` піднімають `ESmartPtrError`, нащадок
  `EInvalidOpException`; подвійного звільнення немає): копії через RTTI
  (`CopyArray`, `TValue`), змінна циклу `for S in Arr`, `SetLength`
  спільного динамічного масиву (після `Arr2 := Arr`) — в останньому випадку
  RTL не звільняє новий блок масиву, тож лишається витік. Копія порожнього
  `TScoped` під час виконання дозволена.
  На компіляторі без `FPC_HAS_NOCOPY_TYPES` діє лише перевірка під час
  виконання.
- Передавайте `TScoped` як `const`, `constref` або `var`. Щоб віддати
  об'єкт іншому власнику — `Move`, `Release` або `Reset`.

```pascal
// Фабрика: Result пишеться прямо у змінну викликача, копії немає.
function LoadLines(N: Integer): TStringListScoped;
var
  I: Integer;
begin
  Result.Reset(TStringList.Create);
  for I := 1 to N do
    Result.Obj.Add('line ' + IntToStr(I));
end;

var
  Lines, Other: TStringListScoped;
begin
  Lines := LoadLines(3);   // результат функції: дозволено
  Other := Lines.Move;     // теж результат функції; Lines порожній
  Lines := Other;          // помилка компіляції: Type "TScoped<...>" cannot be copied
end;
```

> **Чому `Create` і `Reset` звільняють старий об'єкт.** Для керованих
> записів FPC передає змінну-приймач прямо як `Result` і **не фіналізує**
> її перед викликом: усередині `TScoped.Create` поле `Result.FObj` ще
> вказує на попередній об'єкт `S`. Тому всі фабрики модуля пишуть у
> `Result` лише через `Reset`. Пишучи власні функції, що повертають
> `TScoped`/`TArc`, робіть так само (`Result.Reset(...)`, а не присвоєння
> приватного поля).

## 3. `TArc<T>` — спільне володіння з атомарним лічильником

### API

| Член | Опис |
|---|---|
| `class function Create(AObj: T): TArc` | Бере `AObj` у володіння, лічильник = 1. |
| `generic function MakeArc<T>(AObj: T): TArc<T>` | Те саме з виведенням типу: `A := MakeArc(TCatalog.Create)`. |
| `procedure Reset(AObj: T = nil)` | Відпускає поточне посилання (останнє — звільняє об'єкт); з `AObj` починає володіти новим. |
| `function IsAssigned: Boolean` | Чи є об'єкт. |
| `function Get: T`, `property Obj: T` | Доступ до об'єкта. |
| `function UseCount: LongInt` | Кількість власників (знімок; для діагностики й тестів). |
| `=`, `<>` | Порівняння за об'єктом. |

Присвоєння, передача за значенням, копіювання масивів і записів
збільшують лічильник; фіналізація зменшує. Об'єкт звільняється в тому
потоці, який відпустив останнє посилання.

### Блок керування

`TArc<T>` і `TWeak<T>` одного об'єкта посилаються на спільний
`TArcBlock` (`Strong`, `Weak`, `Obj`), що виділяється в `Create`:

- `Strong` — кількість `TArc`; коли стає 0, викликається `Obj.Free`;
- `Weak` — кількість `TWeak` плюс одне посилання, яке тримають усі `TArc`
  разом; коли стає 0, звільняється сам блок.

Усі зміни лічильників — `InterlockedIncrement`/`InterlockedDecrement`/
`InterlockedCompareExchange`. Якщо виділити блок не вдалося, `Create`
звільняє переданий об'єкт (власність уже передано) і перекидає виняток.

### Потокобезпечність

| Дія | Безпечно? |
|---|---|
| Різні змінні `TArc` одного об'єкта копіюються, передаються, знищуються в різних потоках | так |
| Останній власник зникає в будь-якому потоці | так, `Free` рівно один раз |
| Кілька потоків **читають** ту саму змінну `TArc` (копіюють з неї) | так |
| Один потік **пише** в змінну `TArc` (`:=`, `Reset`), а інший її читає чи пише | **ні** — як і `std::shared_ptr`, синхронізуйте (`TCriticalSection`, `TSlimReaderWriterLock`) або дайте кожному потоку власну копію |
| Доступ до полів самого об'єкта | `TArc` керує лише часом життя; захист даних об'єкта — ваша відповідальність |

### Передача в задачі `System.Threading`

Анонімні функції захоплюють **змінну**, а не значення: усі замикання
бачать ту саму змінну `TArc`, і якщо головний потік змінить її (`Reset`),
задачі побачать зміну — це запис у змінну, яку читає інший потік.
Щоб кожна задача мала **власну копію**, створюйте замикання у функції,
що отримує `TArc` параметром за значенням:

```pascal
function StartLookup(Catalog: TCatalogArc; const Key: string): specialize IFuture<Integer>;
begin
  // Catalog — власна копія цієї задачі; вона живе, поки живе замикання.
  Result := TTask.specialize Future<Integer>(
    function: Integer
    begin
      Result := Catalog.Obj.Names.IndexOf(Key);
    end);
end;

Catalog := TCatalogArc.Create(TCatalog.Create);
for I := 0 to High(Keys) do
  Lookups[I] := StartLookup(Catalog, Keys[I]);
Catalog.Reset;   // безпечно: задачі тримають свої копії
```

## 4. `TWeak<T>` — посилання без володіння

### API

| Член | Опис |
|---|---|
| `class function Create(constref A: TArcT): TWeak`, `procedure Assign(constref A: TArcT)` | Почати спостерігати за об'єктом `A`. |
| `function Lock: TArcT` | Атомарно отримати власника (порожній `TArc`, якщо об'єкт уже звільнено). |
| `function TryLock(out A: TArcT): Boolean` | Те саме з результатом-ознакою. |
| `function Expired: Boolean` | Чи звільнено об'єкт (знімок). |
| `procedure Reset` | Перестати спостерігати. |

`TWeakX.TArcT` — це `specialize TArc<T>` з тим самим `T`.

`Lock` збільшує `Strong` лише з ненульового значення (цикл CAS), тому
об'єкт, останній власник якого вже зник, ніколи не «воскресає»:
або `Lock` повертає живий об'єкт, який гарантовано не звільниться,
поки ви тримаєте результат, або порожній `TArc`.

### Розрив циклів

Два об'єкти, що тримають `TArc` один на одного, ніколи не звільняться.
Зворотні посилання (дитина → батько, підписник → видавець, кеш) робіть
через `TWeak`:

```pascal
type
  TNode = class;
  TNodeArc = specialize TArc<TNode>;
  TNodeWeak = specialize TWeak<TNode>;
  TNode = class
    Parent: TNodeWeak;            // не тримає батька
    Children: array of TNodeArc;  // володіє дітьми
  end;
```

## 5. Пастки й правила

1. **Тимчасові значення живуть до кінця підпрограми.** Результат функції,
   використаний у виразі без присвоєння змінній (`W.Lock.Obj.Value`,
   `P(TArcX.Create(...))`, `Watch.Lock.IsAssigned`), FPC зберігає в
   прихованій тимчасовій змінній і фіналізує лише на виході з підпрограми
   (для головної програми — в її кінці). Такий тимчасовий `TArc` утримує
   об'єкт довше, ніж очікується. Якщо момент звільнення важливий —
   присвойте результат змінній і викличте `Reset`:
   ```pascal
   L := W.Lock;
   if L.IsAssigned then
     Use(L.Obj);
   L.Reset;
   ```
2. **Один об'єкт — один блок керування.** Не передавайте в `TArc.Create`
   об'єкт, яким уже володіє інший `TArc` (`B := TArcX.Create(A.Obj)`) чи
   будь-хто інший — буде подвійне звільнення. Копіюйте сам `TArc`:
   `B := A`. (`A.Reset(A.Obj)` розпізнається і нічого не робить.)
3. **Не звільняйте об'єкт вручну** (`S.Obj.Free`) — для `TScoped`
   використовуйте `Reset`, для `TArc` — відпустіть усі посилання.
4. **`TScoped` — лише `const`/`var`-параметри.** Параметр за значенням —
   помилка компіляції (зі старим компілятором — `ESmartPtrError` під час
   виконання). Не перебирайте масив `TScoped` через `for S in Arr` — змінна
   циклу є копією (виняток під час виконання); використовуйте індекс.
5. **Пул потоків утримує останню задачу.** Робочий потік
   `System.Threading.TThreadPool` тримає посилання на щойно виконану
   задачу (а з нею — замикання і захоплені `TArc`), доки не візьме
   наступну. Об'єкт, яким востаннє володіло замикання, звільняється не
   одразу після `Future := nil`, а пізніше. Витоку немає (перевірено
   heaptrc), але не покладайтеся на точний момент.

## 6. Фабрики з виведенням типу й рішення щодо компілятора

### `MakeScoped` / `MakeArc`

```pascal
{$modeswitch implicitfunctionspecialization}   // у модулі, що викликає
var
  L: specialize TScoped<TStringList>;
  C: specialize TArc<TCatalog>;
begin
  L := MakeScoped(TStringList.Create);   // T = TStringList виводиться
  C := MakeArc(TCatalog.Create);
end;
```

Семантика та сама, що в `TScoped.Create`/`TArc.Create`: попередній об'єкт
(посилання) змінної-приймача звільняється. Без перемикача режиму —
`specialize MakeScoped<TStringList>(...)`.

Фабрики потребують компілятора з виправленням forward-оголошень обмежених
дженериків (макрос `FPC_HAS_CONSTRAINED_GENERIC_FORWARD`, ця гілка). Раніше
реалізація функції, оголошеної в `interface` як `<T: class>`, не могла мати
в заголовку `specialize TScoped<T>`: у реалізації обмеження не повторюються,
і необмежений `T` не проходив перевірку `T: class` (`Class type expected`).
Тепер така перевірка заголовка відкладається до зіставлення з оголошенням
(`proc_add_definition`); якщо оголошення не знайдено — повторюється з тими
самими помилками. На старому компіляторі модуль компілюється без фабрик.

Виведення `T` з параметра типу `specialize TXxx<T>` (наприклад, функції,
що приймає `TScoped<T>`) теж працює, зокрема для модуля, який компілюється
в тому самому запуску компілятора (до виправлення `free_localsymtables`
давало `Wrong number of parameters` або `Internal error 2021020905`).

### Чому немає неявних перетворень

Оператор неявного перетворення між записом і `T: class` технічно можливий
(`class operator :=` у `{$mode objfpc}`, `Implicit` у `{$mode delphi}`;
див. тести `tgenconstraint56/57`), але в модулі його **свідомо немає**:

- `S := TStringList.Create` приховувало б передачу володіння;
- `S2 := S1.Obj` тихо компілювалося б і давало подвійний `Free`;
- неявне `L: TStringList := S` видавало б сирий вказівник поза контролем
  власника.

Тому доступ — через `.Obj`/`.Get`, створення — через `Create`/`Reset`/
`MakeScoped`/`MakeArc`.

### Копіювання `TScoped`

Статична заборона — директива `end nocopy;` (ознака компілятора
`FPC_HAS_NOCOPY_TYPES`, [ADR-0008](../adr/0008-nocopy-types.md)); перевірка
`AddRef`/`Copy` під час виконання лишається для копій поза кодом
користувача (див. п. 2).

## 7. Тести й приклад

- fpcunit: `packages/rtl-objpas/tests/utcsmartptrs.pp` (44 тести:
  `TTestScoped`, `TTestArc`, `TTestWeak`, `TTestArcStress`), входять до
  `testrunner.rtlobjpas.pp`. Окремий запуск:
  ```sh
  tests/concurrency/build-smartptrs.sh            # збірка + запуск
  tests/concurrency/build-smartptrs.sh "" -gh     # з heaptrc (0 витоків)
  ```
  Стрес-тести: 8 потоків × 200 000 копій одного `TArc`; 500 раундів
  гонки за останнє звільнення; 500 раундів `TWeak.Lock` проти звільнення
  останнього власника. Перевіряється, що об'єкт звільняється рівно один
  раз і ніколи не звільняється, поки ним хтось володіє.
- Приклад: [`examples/smart_pointers.pp`](../examples/smart_pointers.pp).
- Довідник API у форматі fpdoc: `packages/rtl-objpas/xml/smartptrs.xml`.
- Дизайн-рішення: [ADR-0007](../adr/0007-smart-pointers.md).
