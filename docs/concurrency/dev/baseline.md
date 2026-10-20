# Базова лінія тестів (до змін гілки)

- Коміт: `171b48a107` (trunk, 3.3.1), 2026-10-18
- Платформа: Linux x86_64, 12 ядер
- Компілятор: `compiler/ppcx64` 3.3.1, зібраний bootstrap-компілятором 3.2.2

## vcl-compat: `packages/vcl-compat/tests/testcompat.lpr`

Збірка й запуск:

```sh
. tests/concurrency/fpcenv.sh
$FPC_TRUNK @"$FPC_CFG" -gl -Fupackages/vcl-compat/src -FU<out> -FE<out> \
  packages/vcl-compat/tests/testcompat.lpr
<out>/testcompat --all --format=plain
```

Результат одного прогону: **697 тестів, 0 помилок, 2 падіння** (13,7 с).

Відомі падіння (не пов'язані з конкурентністю, не виправляємо в цій гілці):

| Тест | Повідомлення |
|---|---|
| `TTestTPath.TestIsPathRooted` | `"/abc.def is rooted" expected: <False> but was: <True>` |
| `TTestJsonSerializerArrays.TestSerializeEmptyArray` | `expected: <[]> but was: <null>` |

Набори `System.Threading` (усі пройшли в одиночному прогоні):

| Набір | Тестів | Час, с |
|---|---|---|
| TTestTExceptionList | 12 | 0,000 |
| TTestAggregateException | 8 | 0,000 |
| TTestSparseArray | 3 | 1,182 |
| TTestWorkStealingQueue | 10 | 2,782 |
| TTestObjectCache | 5 | 0,001 |
| TTestObjectCaches | 3 | 0,000 |
| TTestThreading | 7 | 1,663 |
| TTestTask | 22 | 4,516 |
| TTestParallel | 3 | 3,503 |

### Стабільність (50 повторних прогонів кожного набору)

Кожен набір запускався окремим процесом 50 разів, з обмеженням 60 с на запуск.

| Набір | Пройшло | Впало | Зависло |
|---|---|---|---|
| TTestSparseArray | 50 | 0 | 0 |
| TTestWorkStealingQueue | 50 | 0 | 0 |
| TTestObjectCache | 50 | 0 | 0 |
| TTestObjectCaches | 50 | 0 | 0 |
| TTestThreading | 50 | 0 | 0 |
| TTestTask | 50 | 0 | 0 |
| TTestParallel | 50 | 0 | 0 |
| TTestTExceptionList | 50 | 0 | 0 |
| TTestAggregateException | 50 | 0 | 0 |

**Разом: 450 запусків, 0 падінь, 0 зависань.**

### Знахідка для Фази 1: повільний `TParallel.For`

`TTestParallel.TestForEvent` окремо триває **20,7 с**, а в загальному прогоні весь набір
займав 3,5 с. `TestForEvent64` — 1,8 с. Ймовірна причина — холодний старт пулу потоків
або повільне очікування в `TParallel.For` (варіант з `TNotifyEvent`-подібним колбеком).
Потрібно дослідити й додати бенчмарк.

## Після виправлень Фази 1 (TParallel.For)

- vcl-compat: **700 тестів** (+3 нові), 0 помилок, ті самі 2 відомі падіння.
- Стрес 50× для 9 наборів: **450/450**, 0 падінь, 0 зависань (17 хв 18 с).
- `TTestParallel.TestForEvent`: стабільно ~1,8 с (раніше 1,7 с або 20,7 с випадково).
- Пул створює до 24 реплік, але одночасно працює ~12 потоків (1,8 с замість
  теоретичних ~0,9 с) — кандидат на оптимізацію росту пулу.

### valgrind --tool=helgrind

Див. [valgrind.md](valgrind.md): після анотацій і двох виправлень —
0 конфліктів у `System.Threading`, 7 у RTL (відкриті задачі).

## Тестовий набір компілятора (`tests/`, `make full`)

Час прогону: 1 хв 10 с (`-j12`). Підсумок `make digest`:

| Показник | Значення |
|---|---|
| Усього тестів | 10442 |
| Компіляцій | 6472 (успішних 4909, очікувано невдалих 1551) |
| Помилок компіляції | 10 |
| Мали не скомпілюватися, але скомпілювались | 2 |
| Запусків | 3970 (успішних 3963, невдалих 7) |
| Пропущено | 628 (інші CPU/ОС, інтерактивні, відомі баги) |

**Відомі падіння (19)** — список `tests/output/x86_64-linux/faillist`:

```
test/opt/tdfa11            test/opt/tdfa8             test/packages/webtbs/tw11142
test/packages/webtbs/tw14265 (*)                      test/timplements4a
test/timplements4b         test/tisoreset             test/tlibrary3
test/tmultilinestring26    test/tset6                 webtbs/tw0876 (потрібні C-бібліотеки)
webtbs/tw11563             webtbs/tw2536b             webtbs/tw39722
webtbs/tw40453             webtbs/tw41487             webtbs/tw41865c
webtbs/tw7756              webtbf/tw3930a
```

(*) Єдиний тест, пов'язаний з потоками: `tw14265` (pthreads, статичне лінкування `-Xt`).
Падає на етапі лінкування: `ld.bfd: cannot find -lgcc`, хоча
`/usr/lib/gcc/x86_64-linux-gnu/13/libgcc.a` існує. Ймовірно, проблема оточення,
а не компілятора; дослідити у Фазі 1.

Решта 18 падінь не стосуються конкурентності. Критерій для гілки: **жодних нових
падінь понад цей список**.

### Стан на 2026-10-20

Повний набір гілки: **2 падіння** — усі є й в upstream (після виправлень обробника сигналів, лінкування, `timplements4a/b`, обмеження розширеного виведення типів перемикачем `implicitgenerics` і перевірки `finalization` для `tdfa8`). Ще 13 тестів набір пропускає як відомі вади (`%KNOWNCOMPILEERROR`/`%KNOWNRUNERROR`), з них 6 позначено в гілці (таблиця нижче). Окремо зібраний актуальний
`upstream/main` (`3f9ea418a2`, з власними тестами) падає на тих самих тестах плюс
`tw11142`, `tisoreset`, `tw39722`, `tw7756`, `tw35136`, `tw11563`, `tw14265`, `tw0876`, `tlibrary3`, `timplements4a/b`, `tdfa8`, які в гілці
виправлено (застарілі тести оновлено, `tisoreset` і `tw11563` — виправлення RTL, `tw14265` і `tw0876` — лінкування, `tlibrary3` — пропущений `uses initc`).

| Тест | Причина | Тип |
|---|---|---|
| `test/tmultilinestring26` | `MultiLineStringTrimLeft` (issue #35827) | вада компілятора |
| `webtbs/tw40453` | `set of T` у дженерик-процедурі режиму Delphi | вада компілятора |

Позначені в гілці як відомі вади (`{ %KNOWNCOMPILEERROR=… }`, набір їх пропускає):

| Тест | Причина |
|---|---|
| `test/opt/tdfa11` | DFA не пов'язує однакові умови запису й читання (`if j=1`): потрібен DFA, чутливий до шляхів виконання |
| `test/tset6` | множини понад 256 елементів: константні множини в компіляторі — `set of 0..255` |
| `webtbs/tw41487` | вказівникові константи й зсуви полів у `{$if}`: нішеве (переклад C-заголовків), у гілці не реалізується |
| `webtbs/tw41865c` | `div`/`mod` для `Currency`: Delphi їх теж не дозволяє; розширення залишено upstream |
| `webtbs/tw2536b` | `stdcall` після `= nil` у типізованій процедурній константі: лише порядок слів (перед `= nil` працює) |
| `webtbf/tw3930a` | `{%FAIL}`: `type TStringList` не окремий тип при присвоєнні; суворіша перевірка зламала б наявний код |

## Інструменти

- Є: `valgrind` 3.22.0 (helgrind/drd/memcheck), `gdb`, `wine` 9.0 (Win64-матриця).
- Бракує (для ARM64-матриці та бенчмарків):
  `sudo apt install qemu-user qemu-user-binfmt binutils-aarch64-linux-gnu libc6-dev-arm64-cross hyperfine`
