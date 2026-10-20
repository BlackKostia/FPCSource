# Посібник користувача: методи для стандартних типів (`{$modeswitch extensionmethods}`)

Розділ 2.7 дорожньої карти ([roadmap.md](../roadmap.md)), пропозиція 4.7
з `proposals/modern_pascal_productivity_and_web_vision.md` («методи-розширювачі»).

## 1. Коротко

Додавати методи до `string`, `Integer`, `TDateTime`, переліків, масивів і
записів у FPC **уже можна**. Механізм називається помічниками типів
(`type helper`, у Delphi `record helper`). Форк не вигадує нового
синтаксису. Він додає один перемикач, що прибирає головну пастку
помічників:

```pascal
{$mode objfpc}{$H+}
{$modeswitch extensionmethods}   // = {$modeswitch typehelpers} + {$modeswitch multihelpers}
uses SysUtils;

type
  TStringEx = type helper for string
    function Initials: string;
  end;
...
  WriteLn(Name.Trim.ToUpper, ' ', Name.Initials);   // TStringHelper (SysUtils) і свій помічник разом
```

## 2. Навіщо окремий перемикач

У FPC для типу діє **лише останній видимий помічник**. Варто оголосити
свій помічник для `string`, і методи `TStringHelper` з SysUtils
(`ToUpper`, `Trim`, `Split`, `Length` …) зникають:

```pascal
{$modeswitch typehelpers}
uses SysUtils;
type
  TStringEx = type helper for string
    function Shout: string;
  end;
...
  S := S.ToUpper;   // Error: Illegal qualifier — TStringHelper сховано
```

Те саме стається, якщо помічник прийшов з іншого модуля, що стоїть у
`uses` після SysUtils. Це найчастіша причина незрозумілої помилки
«Illegal qualifier».

`{$modeswitch multihelpers}` дозволяє кільком помічникам одного типу діяти
одночасно. Без нього власні методи для стандартних типів майже не
використати, але про нього мало хто знає. `extensionmethods` вмикає обидва
перемикачі одним рядком.

Наявні перемикачі `typehelpers` і `multihelpers` форк не змінює: з ними
окремо компілятор поводиться як upstream FPC.

## 3. Увімкнення

```pascal
{$mode objfpc}{$H+}
{$modeswitch extensionmethods}
```

| Режим | Без перемикача | З `extensionmethods` |
|---|---|---|
| `objfpc` | вбудовані помічники SysUtils (`S.ToUpper`, `I.ToString`) працюють; оголосити свій `type helper for Integer` не можна | свої `type helper` для будь-яких типів, разом з помічниками SysUtils |
| `delphi` | `record helper for string` можна, але він ховає `TStringHelper` | помічники співіснують |

`{$modeswitch extensionmethods-}` вимикає і `typehelpers`, і
`multihelpers`.

## 4. Для яких типів

```pascal
type
  TWeekday = (Mon, Tue, Wed, Thu, Fri, Sat, Sun);
  TPrices = array of Double;
  TPoint2 = record X, Y: Integer; end;

  TStringEx   = type helper for string     ...
  TIntegerEx  = type helper for Integer    ...
  TDoubleEx   = type helper for Double     ...
  TDateTimeEx = type helper for TDateTime  ...   // окремий тип, не Double
  TWeekdayEx  = type helper for TWeekday   ...   // переліки
  TPricesEx   = type helper for TPrices    ...   // іменовані масиви
  TPointEx    = type helper for TPoint2    ...   // записи
  TObjectEx   = class helper for TObject   ...   // класи
```

Усередині методу `Self` — значення, на якому викликано метод. Для
записів і масивів поля та елементи доступні як у звичайному методі.

Вбудовані помічники SysUtils: `TStringHelper` (для `string`, а також
`TAnsiStringHelper`, `TUnicodeStringHelper`, `TWideStringHelper`,
`TShortStringHelper`), помічники для всіх цілих (`TIntegerHelper`,
`TInt64Helper`, `TByteHelper` …), дійсних (`TSingleHelper`,
`TDoubleHelper`, `TExtendedHelper`), `TCurrencyHelper`, логічних
(`TBooleanHelper` …) і `TGuidHelper`.

## 5. Як вибирається метод

З `extensionmethods` (`multihelpers`) компілятор розглядає всі помічники
типу, видимі в цьому місці:

1. **Для кожного імені методу** перемагає найближчий помічник, у якому це
   ім'я є: оголошений пізніше в модулі або в модулі, що стоїть пізніше в
   `uses`. Інші методи інших помічників лишаються доступними.
2. **Перевантаження з різних помічників не об'єднуються.** Якщо
   `THa.Fmt(string)` і `THb.Fmt(Double)` належать різним помічникам, то
   `I.Fmt('s')` — помилка: для імені `Fmt` діє лише `THb`.
3. **Порядок `uses` для різних імен не важливий.** `S.Words` з власного
   модуля і `S.ToUpper` з SysUtils працюють за будь-якого порядку.

## 6. Пастки

**Точний тип.** Помічник прив'язаний до свого типу, а не до «схожих»
типів. На x86_64 `I + 1` для `Integer` має тип `Int64`, тож
`(I + 1).Squared` з помічника для `Integer` — помилка «Illegal
qualifier». Пишіть `Integer(I + 1).Squared` або оголосіть помічник для
`Int64`.

**Імена всередині помічника.** У методі помічника неуточнені імена
спершу шукаються серед методів **усіх** помічників типу. Тому в
помічнику для `string` виклик `Trim(Self)` знаходить
`TStringHelper.Trim(array of Char)`, а не функцію `SysUtils.Trim`, і дає
помилку типу. Пишіть `Self.Trim` або `SysUtils.Trim(Self)`.

**Числові літерали.** `5.ToString` не розбирається, бо `5.` читається як
дійсне число. Пишіть `Integer(5).ToString`. Рядкові літерали працюють:
`' x '.Trim`.

**Лише методи.** Помічник не може додати поле, віртуальний метод чи
реалізацію інтерфейсу. Методи, властивості з геттерами/сетерами та
`class`-методи — можна.

**Без дженериків.** `type helper<T> for TArray<T>` не підтримується.
Помічник пишеться для конкретного типу (`TPrices = array of Double`).

## 7. Без перемикача: успадкування помічника

Сумісний з upstream FPC і Delphi спосіб не втратити `TStringHelper` —
успадкувати від нього свій помічник:

```pascal
{$modeswitch typehelpers}
uses SysUtils;
type
  TStringEx = type helper(TStringHelper) for string
    function Shout: string;
  end;
```

Так працює і без `multihelpers`, але лише один ланцюжок помічників на тип.
Два незалежні модулі з власними помічниками для `string` так не
поєднати, а з `extensionmethods` — можна.

## 8. Приклад

```pascal
{$mode objfpc}{$H+}
{$modeswitch extensionmethods}
uses SysUtils;

type
  TIntegerEx = type helper for Integer
    function Plural(const One, Many: string): string;
  end;

function TIntegerEx.Plural(const One, Many: string): string;
begin
  if Self = 1 then
    Result := Self.ToString + ' ' + One       // ToString — з TIntegerHelper (SysUtils)
  else
    Result := Self.ToString + ' ' + Many;
end;

var
  N: Integer;
begin
  N := 3;
  WriteLn(N.Plural('file', 'files'));          // 3 files
end.
```

Повний приклад — [`examples/extension_methods.pp`](../examples/extension_methods.pp):
рядки, цілі, `TDateTime`, переліки й масиви разом з методами SysUtils.

## 9. Тести

`tests/test/textmeth1` (з модулем `uextmeth1`):
- власні помічники для `string`, `Integer` (два одночасно), `Double`,
  `TDateTime`, переліку, масиву, запису, `class helper` для `TObject`;
- методи SysUtils поруч із власними, помічник з іншого модуля;
- однакове ім'я в двох помічниках (перемагає найближчий);
- виклики на результатах виразів, приведення `Integer(I + 1)`;
- `Self.Trim` і `SysUtils.Trim` у методі помічника.

`textmeth2` — режим `delphi` (`record helper`).

`textmeth3`–`6` (`{%FAIL}`):
- лише `typehelpers`: власний помічник ховає `TStringHelper` (поведінка
  upstream не змінилася);
- без перемикача помічник для `Integer` у `objfpc` неприпустимий;
- `extensionmethods-` вимикає помічники;
- перевантаження з різних помічників не об'єднуються.

Наявні тести помічників набору (`thlp*`, `tthlp*`, `tmshlp*`) проходять
без змін.
