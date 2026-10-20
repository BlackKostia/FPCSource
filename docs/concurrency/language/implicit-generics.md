# Посібник користувача: `{$modeswitch implicitgenerics}` — необов'язковий `specialize` і виведення типів

Розділ 2.1 дорожньої карти ([roadmap.md](../roadmap.md)). Перемикач форку;
у штатному Free Pascal його немає.

## 1. Що вмикає перемикач

```pascal
{$mode objfpc}
{$modeswitch implicitgenerics}
```

1. **Необов'язковий `specialize`** у режимі `objfpc` — для типів, викликів
   процедур і методів, операторів `is`/`as`:
   ```pascal
   var
     List: TFPGList<Integer>;            // замість specialize TFPGList<Integer>
   ...
   Fut := TTask.Future<string>(...);     // замість TTask.specialize Future<string>
   ```
2. **Виведення типових параметрів** узагальнених підпрограм з аргументів
   виклику (`Run(@DoCallback)` замість `specialize Run<Integer>(@DoCallback)`).
   Перемикач сам вмикає штатний `implicitfunctionspecialization` і розширює
   його виведення (розділ 2).

## 2. `implicitgenerics` і штатний `implicitfunctionspecialization`

Штатний перемикач FPC `{$modeswitch implicitfunctionspecialization}` теж
виводить типи з аргументів, але лише в простих випадках. У форку він
поводиться **точно як в upstream FPC**: код, що компілюється (або ні) на
звичайному FPC, поводиться у форку так само. Розширене виведення працює
**лише** з `{$modeswitch implicitgenerics}`.

| Що виводиться | `implicitfunctionspecialization` (як FPC) | `implicitgenerics` (форк) |
|---|---|---|
| `T` зі значень аргументів (`MaxValue(3.14, 2.71)`) | так | так |
| `T` з процедурної змінної узагальненого процедурного типу без констант | так | так |
| `T` з типу повернення та параметрів анонімних функцій і `reference to` (`TTask.Future(function: string ...)`, стрілкові функції) | ні | так |
| `T` через узагальнений процедурний тип з **константним** параметром (`TProc<T, 10>`) | ні | так |
| підпрограми й методи з прихованими параметрами (`Self`, результат) — порівнюються лише видимі | ні | так |
| `specialize` можна не писати в `objfpc` | ні | так |

Приклад: процедурний тип з константним параметром (значенням за
замовчуванням).

```pascal
{$mode objfpc}
{$modeswitch implicitgenerics}

type
  generic TProc<T; const U: integer> = procedure(value: T = U);

generic procedure Run<T>(proc: specialize TProc<T, 10>);
begin
  proc();            // value = 10
end;

procedure DoCallback(value: integer);
begin
  WriteLn(value);
end;

begin
  Run(@DoCallback);  // T = Integer, друкує 10
end.
```

З `{$modeswitch implicitfunctionspecialization}` замість `implicitgenerics`
цей код, як і в FPC, не компілюється («Wrong number of parameters
specified for call to "Run"»), тож тип треба вказати явно:
`specialize Run<Integer>(@DoCallback)`. Невідповідний тип і з
`implicitgenerics` дає помилку: `Run(@DoStr)` для
`procedure DoStr(value: string)` — «Incompatible types».

## 3. Сумісність

- Код без `{$modeswitch implicitgenerics}` компілюється форком так само, як
  штатним FPC, — перемикач потрібно вмикати явно, як і інші розширення
  форку (`arrowfunctions`, `tuples`).
- Код з `{$modeswitch implicitgenerics}` компілюється лише форком.
  Щоб він збирався і на FPC, вказуйте `specialize` і типові параметри
  явно.

## 4. Тести

- `tests/concurrency/test_implicit_generics.pp` — сценарії перемикача
  (`specialize`, виведення через анонімні функції, `TTask.Future`, `ThenBy`).
- `tests/test/timplgen1.pp` — виведення через процедурний тип з
  константою з `implicitgenerics`; `timplgen2.pp` — невідповідний тип
  відхиляється.
- `tests/test/timpfuncspez15.pp` (upstream, `{%FAIL}`) — той самий код зі
  штатним `implicitfunctionspecialization` не компілюється, як у FPC.
