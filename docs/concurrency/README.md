# Конкурентність у FPC (гілка feature/concurrency)

Документація робіт з розвитку багатопоточності, асинхронного I/O та async/await
у цьому форку Free Pascal.

**Цільова платформа — x86_64-linux**: лише на ній гілка підтримується й
тестується ([ADR-0011](adr/0011-target-platform.md)).

## Структура

| Файл / тека | Зміст |
|---|---|
| `modern-concurrency-reference.md` | **Повний довідник API (у стилі MSDN / Qt Docs)**: єдиний систематизований посібник з архітектурою, порівняльною матрицею («When to use what»), детальним описом усіх нових класів, сигнатурами методів, гарантіями потокобезпеки, RAII-гардами, прикладами та реактивними конвеєрами |
| `concurrency-guide.pdf` | **Що нового**: огляд змін, порівняння та приклади (генерується `build_pdf.py`) |
| `guide-system-threading.md` | **Посібник користувача `System.Threading`**: API, шаблони використання (`For`, `Break`/`Stop`, `Join`, `IFuture`, `ContinueWith`/`ThenBy`/`Map`, `TCancellationToken`, `WaitForAll`/`WaitForAny`, `TThreadPool`), правила безпеки |
| `guide-syncobjs.md` | **Посібник користувача `SyncObjs` (Фаза 2)**: `TCountdownEvent`, `TBarrier`, `TSlimReaderWriterLock` (+ RAII-гарди), `TChannel<T>` (CSP-канали та `for..in`) |
| `guide-eventloop.md` | **Посібник користувача `fcl-eventloop` (Фаза 1.3)**: `IEventLoop`, `TEventLoopGroup`, неблокуючі сокети C100K+, пайпи, файли, таймери Min-Heap, інтеграція з `IFuture` та `TCancellationToken` |
| `guide-arrow-functions.md` | **Посібник користувача стрілкових функцій (Розділ 2.2)**: синтаксис `=>`, скорочення шаблонного коду в `System.Threading` та `fcl-async`, виведення типів параметрів і результату |
| `guide-tuples.md` | **Посібник користувача кортежів та деконструкції (Розділ 2.4)**: позиційні та іменовані кортежі, деконструкція `(A, B) := Expr`, inline-розпакування `var (A, B) := ...`, одночасний swap `(X, Y) := (Y, X)`, структурна еквівалентність |
| `guide-async.md` | **Посібник користувача `fcl-async` та `async/await` (Фаза 1.4)**: `TFiber` (стекові корутини System V AMD64), `TGenerator<T>` (`for..in`), `TTaskCompletionSource<T>`, компіляторна директива `async` та оператор `await` |
| `guides/smart-pointers.md` | **Посібник користувача розумних вказівників (Розділ 3.1)**: `TScoped<T>` (одноосібне володіння без `try..finally`), `TArc<T>` (атомарний підрахунок посилань між потоками), `TWeak<T>` (розрив циклів), пастки тимчасових значень і замикань |
| `guides/spans.md` | **Посібник користувача зрізів пам'яті (Розділ 3.2)**: `TSpan<T>` / `TReadOnlySpan<T>` без копіювання, `Slice`, `Chunk` для паралельних задач, перевірка меж, рядки, правила часу життя |
| `guides/tsan.md` | **Посібник ThreadSanitizer (Розділ 3.3)**: ключ `-fsanitize=thread`, запуск під `setarch -R`, що інструментується, анотації `TsanRelease`/`TsanAcquire` для атомарних операцій, обмеження; тести — `tests/concurrency/run-tsan.sh` |
| `guides/asan.md` | **Посібник AddressSanitizer (Розділ 3.3)**: ключ `-fsanitize=address`, що знаходить (переповнення купи, use-after-free, подвійне звільнення, витоки), стеки у звітах, `AsanPoison`/`AsanUnpoison` для власних аллокаторів, обмеження; тести — `tests/concurrency/run-asan.sh` |
| `examples/` | Приклади з документації (`parallel_for.pp`, `tasks.pp`, `pool_lifetime.pp`, `valgrind_annotate.pp`, `primes_*`, `report_*`, `batch_processing.pp`, `showcase_pipeline.pp`, `syncobjs_phase2.pp`, `continuations_cancel.pp`, `eventloop_benchmark.pp`, `coroutine_showcase.pp`, `smart_pointers.pp`, `spans_parallel.pp`); кожен компілюється й запускається |
| `valgrind.md` | Перевірка гонок даних (helgrind/drd), анотації, відомі обмеження |
| `baseline.md` | Базова лінія тестів trunk до наших змін (відомі падіння) |
| `adr/` | Дизайн-рішення (ADR-0001: життєвий цикл потоків пулу; ADR-0002: клієнтські запити Valgrind; ADR-0003: детермінованість `TParallel.For` і `Join`; ADR-0004: примітиви `SyncObjs` Фази 2; ADR-0005: неблокувальні продовження та `TCancellationToken`; ADR-0006: масштабований асинхронний I/O `fcl-eventloop`; ADR-0007: розумні вказівники на керованих записах; ADR-0008: некопійовані типи `end nocopy`; ADR-0009: зрізи пам'яті `TSpan<T>`; ADR-0010: ThreadSanitizer у генераторі коду; ADR-0011: цільова платформа x86_64-linux; ADR-0012: AddressSanitizer у генераторі коду) |
| `roadmap-improvements.md` | **Дорожня карта розвитку FPC**: рекомендації щодо бібліотек багатопоточності (Фази 2–4), синтаксичної ергономіки компілятора, безпеки пам'яті та інструментарію |
| `../../packages/rtl-objpas/xml/fpvalgrind.xml` | Довідник API `fpvalgrind` у стандартному форматі `fpdoc` |
| `../../packages/rtl-objpas/xml/spans.xml` | Довідник API модуля `spans` (`TSpan`, `TReadOnlySpan`) у стандартному форматі `fpdoc` |
| `../../packages/rtl-objpas/xml/smartptrs.xml` | Довідник API модуля `smartptrs` (`TScoped`, `TArc`, `TWeak`) у стандартному форматі `fpdoc` |
| `../../packages/fcl-base/xml/syncobjs-phase2.xml` | Довідник API нових примітивів `SyncObjs` (Фаза 2) у стандартному форматі `fpdoc` |
| `../../packages/fcl-eventloop/xml/fcleventloop.xml` | Довідник API пакету `fcl-eventloop` (Фаза 1.3) у стандартному форматі `fpdoc` |
| `../../packages/vcl-compat/xml/system.threading.xml` | Довідник API `System.Threading` у стандартному форматі `fpdoc` |
| `../../CHANGELOG-concurrency.md` | Журнал змін гілки |

## Фази

0. Інфраструктура: збірка, baseline тестів, CI.
1. Стабілізація `System.Threading` (`packages/vcl-compat`).
2. Нові примітиви синхронізації (`packages/fcl-base/src/syncobjs.pp`).
3. Асинхронний I/O: пакет `packages/fcl-eventloop`.
4. async/await (Фаза 1.4):
   - **Крок 1 (бібліотечний)**: легковагові корутини/файбери (`TFiber`), генератори `TGenerator<T>`, скінченні автомати (`TTaskCompletionSource<T>`, `TAsyncTaskMethodBuilder<T>`) у новому пакеті `packages/fcl-async/`.
   - **Крок 2 (у компіляторі)**: процедурна директива `async` та оператор `await` у `compiler/ppcx64`. Повна сумісність з PPU/RTL.

## Definition of Done

Кожна зміна містить: код, fpcunit-тести, стрес-тест (якщо є паралелізм),
fpdoc-опис API, приклад у `examples/`, запис у `CHANGELOG-concurrency.md`.

## Збірка

```sh
make clean PP=<шлях до ppcx64 3.2.2>
make all PP=<шлях до ppcx64 3.2.2> FPMAKEOPT="-T 12" -j12
```

`clean` і `all` — окремими командами: у `make clean all -j12` цілі
виконуються паралельно, і `all` може вирішити, що все вже зібрано
(stamp-файл), коли `clean` уже все видалив — у результаті немає навіть
`compiler/ppcx64`. Не компілюйте модулі пакетів вручну без `-FU`: `.ppu`
у `packages/*/src` перекривають результат fpmake (`Can't find unit
contnrs` під час `make all`).

```sh
```

**Важливо:** шлях до дерева джерел не повинен містити пробілів — makefile-и FPC
ламаються з помилкою `Only one source file supported`. Тому робоча копія гілки —
git worktree `/home/chessplayer/DEV/Pascal/fpc-concurrency`.

### Встановлення trunk у домашню теку (потрібно для `tests/`)

Тестовий набір компілятора очікує «встановлений» FPC з `fpc.cfg`:

```sh
make install INSTALL_PREFIX=$HOME/fpc-trunk PP=$PWD/compiler/ppcx64
mkdir -p ~/fpc-trunk/etc
~/fpc-trunk/bin/fpcmkcfg -d basepath=$HOME/fpc-trunk/lib/fpc/3.3.1 -o ~/fpc-trunk/etc/fpc.cfg
export PPC_CONFIG_PATH=$HOME/fpc-trunk/etc
export PATH=$HOME/fpc-trunk/bin:$PATH   # потрібен fpcmake
cd tests && make full TEST_FPC=$HOME/fpc-trunk/lib/fpc/3.3.1/ppcx64 \
                      FPC=$HOME/fpc-trunk/lib/fpc/3.3.1/ppcx64 -j12
```

Bootstrap-компілятор 3.2.2 розпаковано без root з пакета Ubuntu
(`apt-get download fp-compiler-3.2.2` + `dpkg -x`) у `~/fpc-bootstrap/root/`.

## Документація PDF

```sh
python3 -m venv /tmp/venv && /tmp/venv/bin/pip install reportlab
/tmp/venv/bin/python docs/concurrency/build_pdf.py
```

Приклади читаються безпосередньо з `examples/*.pp`; після зміни прикладу
перевірте його (`fpc` з `tests/concurrency/fpcenv.sh`) і перегенеруйте PDF.
