# Журнал змін: гілка feature/concurrency

## [Unreleased]

### Виправлено
- Компілятор: розширене виведення типів форку (`36cb34ccbc`: процедурні
  типи з константами, анонімні функції й `reference to`, приховані
  параметри) діяло й у штатному `{$modeswitch implicitfunctionspecialization}`,
  тож форк компілював код, який FPC відхиляє (тест upstream
  `timpfuncspez15`, `{%FAIL}`). Тепер розширена версія `handle_procvars`
  (`pgenutil.pas`) працює лише з `{$modeswitch implicitgenerics}`, а без
  нього — повернута функція upstream. Нові тести `tests/test/timplgen1`
  (виведення через `TProc<T, 10>` з `implicitgenerics`) і `timplgen2`
  (невідповідний тип відхиляється); посібник
  `docs/concurrency/language/implicit-generics.md`. Падінь у `tests/` — 9.
- Тести `timplements4a`/`4b` (2008) чекали винятку від `QueryInterface`
  інтерфейсу, отриманого через `implements` властивістю класового типу,
  після `o1.fi := nil` / `o1.free`. Але такий інтерфейс — це інтерфейс
  самого делегата з власним посиланням (як у Delphi), тож запит законно
  успішний; тести падали й на релізі 3.2.4. Тепер вони перевіряють саме
  це: інтерфейс лишається дійсним і тримає делегата, об'єкт без делегата
  інтерфейсу не надає, витоків немає (`HaltOnNotReleased`). Падінь у
  `tests/` — 10.
- Лінкування на x86_64-linux із сучасними glibc/GCC:
  - компілятор сам знаходить теку бібліотек GCC (`gcc -print-file-name`),
    коли її немає серед шляхів пошуку (наприклад, з `-n`, без `fpc.cfg`):
    звідти беруться `crtbegin*.o`/`crtend*.o` і `libgcc.a`. Раніше `-pg`
    давав `undefined reference to __dso_handle`, а `-Xt` —
    `cannot find -lgcc`. Пошук `libtsan`/`libasan` використовує той самий
    метод `TExternalLinker.AddGCCLibraryPath`; для крос-цілей питається
    лише `gcc` з префіксом утиліт;
  - статичні програми (`-Xt`) з libc: стартовий код FPC (`si_c`) замість
    `crt1.o` тепер визначає порожню слабку `_dl_relocate_static_pie`, яку
    викликає `__libc_start_main` у glibc зі static-pie (2.27+); інакше
    лінкер брав версію з `libc.a`, що потребує `_DYNAMIC`;
  - тест `tlibrary3`: блок `uses initc`, який upstream (`8b48127b2c`)
    додав у `tlibrary2` та інші тести бібліотек, при переписуванні тесту
    випав; програма без libc з динамічними бібліотеками не запускається
    із сучасним `ld.so` (`undefined symbol: calloc`).
  Тести `tw14265`, `tw0876`, `tlibrary3` проходять; падінь у `tests/` — 12.
- RTL x86_64-linux: необроблена помилка (SIGSEGV/SIGBUS/SIGILL) там, де
  стек не вирівняний на 16 байтів (наприклад, збій на першій інструкції
  викликаної процедури — виконання зі стеку), зациклювала обробник:
  трамплін `SignalToHandleErrorAddrFrame` імітував виклик
  `HandleErrorAddrFrame` без вирівнювання, і вирівняний SSE-доступ у
  `Dump_Stack` викликав новий збій. Тепер трамплін вирівнює `rsp`; тест
  `tests/webtbs/tw11563` проходить (один runtime error 216 і код виходу
  216 замість нескінченного виводу й SIGSEGV).
- RTL: `reset` порожнього типізованого файлу в ISO-режимі давав runtime
  error 100. Виправлення upstream (!1371) потрапило лише в
  `fpc_reset_typed_name_iso`, а компілятор викликає `fpc_reset_typed_iso`;
  ту саму перевірку `eof` додано й туди. Тест `tests/test/tisoreset`
  тепер проходить.
- Застарілі тести набору `tests/` оновлено під навмисні зміни upstream:
  `tw11142` (після переходу `TFPHashList` на MurmurHash3 колізії
  дозволені; тест перевіряє коректність пошуку й ланцюжків колізій),
  `tw7756` (`FloatToDecimal` з точністю понад 17 повертає 19 значущих
  цифр, issue #41189; оновлено 30 очікуваних значень, звірених з точним
  значенням `Double`), `tw39722` (`dotest` з 2024 року запускає компілятор
  без оболонки, тож `\$` у `%opt` доходив до компілятора; тепер одинарні
  лапки). Падінь у `tests/` — 16 (було 20), нових немає.
- Тест `tests/webtbs/tw35136` (ISO-режим) застарів після коміту upstream
  `5a1434bc05` (issue #40444): за ISO 7185 рядок без завершального кінця
  рядка отримує неявний `eoln` перед `eof`, тож після читання останнього
  символу `eof` ще не встановлено. Тест тепер перевіряє `eoln`, відсутність
  передчасного `eof` і `eof` після наступного `get`; RTL не змінювався.
- `-fsanitize=thread`: неправильний розмір доступу для SSE-`movsd`
  (16 байтів замість 8: опкод спільний із рядковою інструкцією), x87
  `flds`/`fldl`/`fldt` (2/4/8 замість 4/8/10) і векторних операндів
  «розміру регістра». Два потоки, що пишуть у сусідні поля `Double`,
  давали хибну гонку. Тест `tests/concurrency/tsan/norace_adjacent_double`
  (на старому компіляторі — звіт про гонку).
- Компілятор: **use-after-free** під час неявної спеціалізації. Після
  компіляції модуля `free_localsymtables` звільняв локальну таблицю символів
  і узагальнених підпрограм, хоча їхні параметри посилаються на визначення
  в ній (`constref B: specialize TBox<T>`). Коли модуль компілювався в тому
  самому запуску, що й програма, виклик `Unbox(B)` давав `Wrong number of
  parameters` або `Internal error 2021020905` (з готовим `.ppu` — працював).
  Тест `tests/test/tgenfunc28` (на старому компіляторі — обидва симптоми).
- Тести `System.Threading`: `TestContinueWithAndOptions` і
  `TestTreeCancellationAndParallelFor` миттєво перевіряли статус
  продовження-«сусіда», яке скасовується в обробниках завершення
  попередньої задачі вже після сигналу `Wait`; тепер чекають статус
  (`WaitForTaskStatus`). Під навантаженням (12 процесів) було 3 падіння зі
  120 прогонів набору, стало 0 із 300.
- Helgrind: `smartptrs` з `-dFPC_VALGRIND` анотує лічильники посилань;
  `fpvalgrind` перенесено з `fcl-base` у `rtl-objpas` (без залежностей,
  потрібен `smartptrs`); у `fpc-helgrind.supp` — виняток для стеку без
  блокувань `incomingToFree` менеджера купи RTL.
- Компілятор: forward-оголошення дженерик-підпрограми з обмеженнями в
  implementation/програмі (де обмеження треба повторювати) з параметром
  типу `T` не зіставлялося з реалізацією: «Function is already declared»
  і **внутрішній збій компілятора**. Тести `tests/test/tgenconstraint41`–`58`
  (18 нових; повний набір `tests/` — без нових падінь відносно baseline).
- RAII-гарди `SyncObjs` (`TLockGuard<T>`, `TSlimReadLockGuard`,
  `TSlimWriteLockGuard`) не мали операторів `AddRef`/`Copy`: копія гарда
  (присвоєння, передача за значенням) при фіналізації **відпускала
  блокування вдруге**. Для `TSlimReadLockGuard` це тихо знімало чуже
  читацьке блокування, для write-гарда — `ELockException` у фіналізації.
  Тепер копія гарда, що тримає блокування, піднімає `ELockException` і нічого
  не відпускає; копія порожнього гарда дозволена. Регресійні тести
  `TTestSyncObjsPhase2.TestSlimReadGuardCopy`, `TestSlimWriteGuardCopy`,
  `TestLockGuardCopy` (на старому коді падають усі три).
- `TThreadPool` (`System.Threading`): задача, поставлена в глобальну чергу саме
  тоді, коли робочий потік ішов у сон, чекала **40 с** (`IdleTimeout`), хоча
  вільні потоки були. Потік перевіряв глобальну чергу до `FQueueEvent.ResetEvent`,
  а після скидання — лише локальні черги інших потоків, тож сигнал про нову
  задачу стирався. Тепер глобальна черга перевіряється й після скидання.
  Помітно було на одиничних `TTask.Run`, `TTask.Future` і продовженнях
  (`ContinueWith`): приблизно кожна сота задача стартувала через 40 с.
  Регресійні тести: `TTestThreading.TestQueuedTaskStartsPromptly`,
  `TestContinuationOfFastFutureRuns` (на старому коді падають на 16–27 раунді).
- `fcl-eventloop`, бекенд io_uring (обирається `bkAuto` на Linux): `DoPoll`
  не чекав подій і ігнорував таймаут, тож цикл крутився на 100 % CPU
  (313 тис. ітерацій `RunOnce(200)` за 200 мс). Крім того, poll перевзводився
  з маскою `POLLIN|POLLOUT` замість зареєстрованих подій (сокет, що чекає
  лише читання, «готовий до запису» постійно), завершення `-ECANCELED` після
  `POLL_REMOVE` оброблялися як події й **ставили poll на вже знятий дескриптор**,
  не було бар'єрів пам'яті на кільцях і захисту від подачі SQE з кількох потоків.
  Бекенд переписано: очікування через `IORING_OP_TIMEOUT` (count = 1),
  `user_data` з номером покоління відсікає застарілі завершення, poll
  перевзводиться з маскою реєстрації, подача SQE під блокуванням.
- `fcl-eventloop`, ядро: `Stop`, викликаний до `Run`, губився, і `Run` крутився
  вічно; через це `TEventLoopGroup.Destroy` (Stop → Wait) зависав, якщо потоки
  ще не ввійшли в `Run`, а група без `Start` зависала завжди. Виняток у
  обробнику вводу-виводу виходив із `Run` і зупиняв цикл (таймери й `Post`
  вже були захищені). Таймери тепер у мін-купі (раніше — лінійний масив з
  повним переглядом на кожному тіку); періодичний таймер з інтервалом 0 більше
  не зациклює `ProcessTimers`.
- `fcl-eventloop`, сокети:
  - `AcceptAsync`: допоміжний об'єкт лишався обробником `accept` після `Free`
    — **use-after-free** на кожному наступному з'єднанні. Обробник тепер
    одноразовий.
  - запис у сокет, закритий протилежною стороною, вбивав процес сигналом
    **SIGPIPE**; тепер `MSG_NOSIGNAL` (`SO_NOSIGPIPE` на Darwin), запис
    завершується з EPIPE/ECONNRESET.
  - `ReadAsync`/`WriteAsync`/`AcceptAsync` займали потік пулу на весь час
    очікування, ігнорували скасування після старту (`.Value` висів вічно) і
    викликали `AsyncRead`/`AsyncWrite` з потоку пулу без синхронізації з
    потоком циклу. Тепер це обіцянки (`eventloop.promise`), операція
    передається в потік циклу, скасування знімає операцію з сокета.
  - помилка асинхронного `connect` кидала виняток із колбека й зупиняла `Run`;
    тепер колбек викликається з `Connected = False`, код помилки — у
    `TAsyncSocket.LastError`.
  - бездіяльний сокет з закритим протилежним кінцем (EPOLLHUP), слухаючий
    сокет без обробника з чергою з'єднань крутили цикл на 100 % CPU; сокет
    тепер зареєстрований у циклі лише поки є очікувана операція.
  - очікуваний запис не завершувався при обриві з'єднання; `Close` тепер
    завершує очікувані операції з ECANCELED (майбутні — скасуванням).
  - ім'я хоста замість IPv4-адреси (`StrToNetAddr` повертав 0.0.0.0) тихо
    з'єднувало з локальною машиною; тепер `ESocketException`.
  - `SO_REUSEPORT` мав значення Linux (15) на всіх Unix.
- `fcl-eventloop`, пайпи: після закриття записувального кінця EPOLLHUP
  крутив цикл на 100 % CPU, а очікуване читання не завершувалося; запис у
  пайп без читача вбивав процес SIGPIPE (тепер SIGPIPE ігнорується, якщо
  програма не встановила власний обробник, — запис отримує EPIPE). Модуль
  підключав `linux` на будь-якому Unix і не компілювався на BSD/macOS.
- `fcl-eventloop`, файли: `OpenFile(Name, fmCreate)` відкривав файл **лише
  для читання** (`fmCreate = $FF00` без бітів доступу), кожен запис падав з
  EBADF; замикання асинхронних операцій не тримали посилання на файл
  (use-after-free, якщо файл звільнити раніше за задачу). Читання й запис зі
  зсувом — через `pread`/`pwrite`.
- `fcl-eventloop`, kqueue: `EV_CLEAR` (фронтовий режим) при одноразовому
  читанні на подію губив дані, що лишилися в буфері; тепер рівневий режим,
  як в epoll. Не перевірено на BSD/macOS (немає середовища).
- `fcl-coroutines`, `TFiber`: `Await`/`Sleep`/`AwaitRead`/`AwaitWrite` без циклу
  подій відновлювали файбер у потоці пулу, коли він ще не встиг віддати
  керування (два потоки на одному стеку); `Destroy` міг звільнити стек, поки
  інший потік ще виконував на ньому останнє перемикання (стан `fsCompleted`
  видно раніше). Тепер відновлення з іншого потоку і `Destroy` чекають
  завершення перемикання. Стек має сторожову сторінку (переповнення падає,
  а не псує пам'ять). Виняток файбера повторно піднімається з тим самим
  класом (раніше — `Exception` з тим самим текстом).
- `fcl-coroutines`, `TGenerator<T>`: виняток виробника звільнявся двічі
  (обробником у споживача і в `Destroy`).
- `fcl-coroutines`, `TTaskCompletionSource<T>`: кожне джерело блокувало потік
  пулу до завершення (кілька десятків очікуваних джерел вичерпували пул —
  взаємне блокування); звільнення незавершеного джерела знищувало подію, на
  якій чекав потік. Тепер задача — не запущене майбутнє, яке стартує лише в
  `SetResult`/`SetException`; звільнення незавершеного джерела скасовує задачу;
  `SetException` зберігає клас винятку. Будівники (`TAsyncTaskMethodBuilder`,
  `TAsyncTaskBuilder`) більше не втрачають джерело (витік).
- `SyncObjs`, `TSlimReaderWriterLock`: читач реєструвався в `FWaitingReaders`
  лише після останньої перевірки, а `EndWrite` читає лічильник без
  блокування — записувач, що виходив у цьому вікні, не будив читача (за
  аналізом коду; у стрес-тесті не відтворилося). `EndRead` без захопленого
  читання під утримуваним записом псував стан замка; тепер `ELockException`.
- `SyncObjs`: перевантаження з від'ємним `TTimeSpan` перетворювались на
  `Cardinal(Round(-x))` — практично нескінченне очікування; тепер 0.
- Компілятор: `await` розпізнавався як оператор у будь-якому режимі й ламав
  код зі змінною, функцією чи полем `await`; тепер — контекстне ключове
  слово (якщо ідентифікатор `await` видимий, він має звичайне значення).
  Тести: `tests/concurrency/test_await_identifier.pp`, `test_await_operator.pp`.
- Збірка: `fcl-eventloop` не був підключений до загальної збірки пакетів
  (`fpmake_add.inc`), а `fcl-async` після переписування `fpmake.pp` більше не
  збирав `fpasync`/`libasync`, від яких залежить `fcl-net` (`fpsock`,
  `httpsvlt`). Повернути їх у той самий пакет не можна: нові модулі залежать
  від `vcl-compat`, а він через `fcl-web` — від `fcl-net`, тож виникає цикл
  `fcl-net → fcl-async → vcl-compat → fcl-web → fcl-net`, на якому паралельний
  `fpmake` зависає назавжди.

- `TThreadPool` (`System.Threading`): на «холодному» пулі `TParallel.For` випадково
  виконувався **послідовно** (255 ітерацій × 80 мс: 20,7 с замість 1,7 с).
  Репліки циклу потрапляли в локальну чергу потоку з кореневою задачею, а вільні
  потоки заглядали в чужі черги лише після сигналу `FQueueEvent`, якого не було,
  поки пул ще створював потоки; без сигналу вони спали до 40 с (`IdleTimeout`).
  Тепер потік перед сном скидає подію і перевіряє чужі черги, а забравши роботу
  при наявності ще незавершених запитів, будить наступний потік.
  Регресійний тест: `TTestParallel.TestForColdPoolParallel`.
- `TParallel.For` (`Integer` і `Int64`): ітерації могли **губитися або виконуватися
  двічі**, при цьому `TLoopResult.Completed = True`. Потік забирав діапазон
  ітерацій з одним значенням кроку (`GetCurrentStart`), а виконував діапазон,
  обчислений з іншим, прочитаним окремо, тоді як інші потоки збільшували крок
  (`GetNextStride`). Тепер `GetCurrentStart(out aStride)` повертає крок, з яким
  діапазон забрано. Помилка була в trunk і раніше; стала помітною після
  попереднього виправлення, коли цикл почав справді працювати паралельно.
  Регресійні тести: `TTestParallel.TestForEachIterationOnce`, `…Once64`
  (200 000 ітерацій × 200 раундів, кожна має виконатися рівно один раз;
  з поверненою гонкою тест падає в 10 з 10 запусків).

- `TTask.GetIsComplete` (швидкий шлях `TTask.Wait`): читання стану без
  блокування не мало бар'єра пам'яті; на ARM64 потік міг побачити задачу
  завершеною раніше за її результат. Додано `ReadBarrier`.
- `TThreadPool.Destroy`: use-after-free. `StopCPUStats` скидав
  `FMonitorStatus` до завершення монітора, `Destroy` звільняв пул, а потік
  монітора потім писав у звільнену пам'ять. Статус тепер скидається атомарно
  останньою дією монітора.
- `TTask.WaitForAny`: результат (`Res`) читався без блокування в умовах
  циклів очікування; тепер під тим самим `Lock`, що й запис.
- Тести `utthreading.pp`: глобальний `Random` викликався з потоків пулу;
  замінено на потокобезпечний `ThreadRandom`.
- `TThreadPool.Destroy` не чекав фактичного завершення потоків: робочі потоки
  й монітор були `FreeOnTerminate` і виходили зі списку пулу у власному
  деструкторі, тож `Destroy` повертав керування, поки вони ще виконували
  деструктор і завершальну частину RTL. Для пулу за замовчуванням це
  перетиналося з фіналізацією програми (вимкнення менеджера пам'яті).
  Тепер потоки належать пулу (`FreeOnTerminate := False`): завершуючись,
  потік переходить у `FFinishedThreads` (раніше, ніж залишає `FThreads`),
  а пул приєднує й звільняє їх (`ReapFinishedThreads`) у моніторі та в
  `Destroy`; монітор зберігається в `FMonitorThread`.
  Регресійний тест: `TTestThreading.TestFreeJoinsThreads` (до виправлення:
  після `Pool.Free` живих потоків 25 замість 1).
- RTL `rtl/unix/tthread.inc` (`ThreadFunc`): новий потік повторно записував
  `FSuspendedInternal := true` без синхронізації; запис міг відбутися після
  того, як `Resume` у потоці-творці вже скинув прапорець. Рядок прибрано
  (значення встановлює `SysCreate` до старту потоку).
- RTL `rtl/unix/cthreads.pp` (`RemoveTidEntries`, `DoneTidEntries`):
  `ThreadTidList` перевірявся без `ThreadTidLock`; тепер лише під блокуванням.
- Тести `utthreading.pp`: потоки тестів (`TNotifyThread`, `TTaskThread`) були
  `FreeOnTerminate` і вважалися завершеними за `OnTerminate`, тобто до
  фактичного завершення; тепер `TThreadedTestCase.TearDown` їх приєднує й звільняє.
- Тести `utthreading.pp`: `Assert*` викликався з робочих потоків
  (`DoSimpleExecute`, `DoBurnCyclesExecute`, `OnTask`, `CalcIntegerEvent`).
  Виняток виникав у потоці, а не в тесті, тож невдала перевірка могла
  залишитися непоміченою; лічильники `fpcunit` не потокобезпечні. Тепер
  ці місця використовують `ThreadCheck`/`ThreadCheckSame`: невдача
  записується під блокуванням, а `TThreadedTestCase.TearDown` після
  приєднання потоків валить тест з переліком невдач.
  Тест механізму: `TTestThreading.TestThreadCheckRecordsFailure`.
- `EAggregateException`: перебір `for E in Agg` видавав зайвий елемент за
  межами масиву (`MoveNext` перевіряв межу до збільшення індексу), а після
  `Add` — ще й порожні місця запасу місткості; програма падала з
  `Access violation`. Тепер перебираються рівно `Count` помилок.
  Тести: `TTestAggregateException.TestEnumerate`, `TestEnumerateAfterAdd`.
- `TWorkStealingQueue.TrySteal`: при `aTimeout = 0` на порожній черзі зайво
  викликалися `FEvent.ResetEvent` і `FEvent.WaitFor(0)` (два системні виклики)
  під спін-блокуванням списку черг пулу, через що вільні потоки переходили в
  `Sleep(1)` у `TSpinWait` і приєднувалися до коротких циклів по одному.
  Тест: `TTestWorkStealingQueue.TestStealNoWaitIsCheap`.
- `TParallel.For` з `TLoopState`, `Break`, `Stop`:
  - `TLoopState` ніколи не створювався (`nil`), тож кожен цикл із параметром
    стану падав з `Access violation`; тепер кожна репліка створює власний
    `TLoopState32`/`TLoopState64` в `Invoke`.
  - `TLoopParams.Break` завжди повертав `False`, тож `FBreakAt` не
    оновлювався; `ShouldExitLoop(CurrentIter)` у режимі `objfpc` читав змінну
    результату замість виклику `ShouldExitLoop()`, тому `Stop` і винятки не
    зупиняли цикл; у `Invoke` викликався `TLoopParams.Break` замість
    `system.Break` та перевірявся `ShouldExitLoop(Start)` замість
    `ShouldExitLoop(I)`.
  - Тести: `TTestParallel.TestForWithState`, `TestForBreak`, `TestForStop`.
- `TParallel.For` і винятки в ітераціях:
  - `TExceptionList.Create(Initial, aCapacity)` не збільшував `Count` і не
    розгортав `EAggregateException`;
  - `FTasksWithExceptions` зберігав необліковувані `TTask` замість `ITask`,
    через що дочірня репліка з винятком знищувалася потоком пулу при
    `Itm := Nil` разом із `FException` ще до того, як коренева задача збирала
    помилки, а `ReplicaCallUserCode` двічі викликав `Complete`.
  - Тест: `TTestParallel.TestForExceptionPreserved`.
- `TThreadPool.Destroy` / `GetWorkItemForThread`: потік міг скинути
  `FQueueEvent.ResetEvent` після `FQueueEvent.SetEvent` у `Destroy`, залишаючи
  інші потоки спати до `IdleTimeout` (40 с).
- `TParallel.Join` (`TProcJoinTask`, `TEventJoinTask`):
  - локальний запис `Params: TTaskParams` не обнулявся (`Default(TTaskParams)`),
    через що поле `Params.Event` містило сміття зі стеку;
  - `Params.Parent := Self` робив задачу дочірньою для самої себе
    (`FSubTasks = 2`), через що `Wait` зависав назавжди;
  - `TParallel.Join` не запускав створену задачу (`.Start`).
  - Тест: `TTestParallel.TestJoin`.

### Змінено
- Цільова платформа гілки — x86_64-linux (ADR-0011): лише на ній гілка
  підтримується й тестується. `fcl-coroutines` обмежено до `linux`
  (раніше — усі Unix, хоча перевірявся лише Linux); у `fcl-eventloop`
  бекенди kqueue та IOCP позначено як непідтримувані; документи більше не
  обіцяють macOS, Windows та ARM64.
- Модулі `async.types`, `async.fiber`, `async.generator`, `async.statemachine`,
  `fclasync` і їхні тести перенесено з `packages/fcl-async` в новий пакет
  `packages/fcl-coroutines` (лише x86_64, Unix); імена модулів не змінились.
  `fcl-async` знову збігається з upstream. `fcl-eventloop` підключено до
  загальної збірки, додано залежність від `vcl-compat` і модуль
  `eventloop.promise`.

### Додано
- AddressSanitizer у рідному генераторі коду (розділ 3.3 дорожньої карти,
  ADR-0012): ключ `-fsanitize=address` для x86_64-linux, макрос
  `FPC_SANITIZE_ADDRESS`; разом із `-fsanitize=thread` — помилка. Прохід
  інструментації спільний із TSan (`compiler/x86/tsaninstr.pas` →
  `saninstr.pas`). Новий модуль `fpcasan` (`rtl-objpas`): трампліни зі
  швидкою перевіркою тіньової пам'яті, звіт «з місця доступу»
  (`__asan_report_load_n/store_n` зі стеком програми), лінкування
  `libasan`, `AsanPoison`/`AsanUnpoison`/`AsanIsPoisoned` для власних
  аллокаторів. Інструментований код завжди має кадр `rbp` (ASan розгортає
  стек за frame pointer). `cthreads` під ASan, як під TSan, викликає
  pthread через перехоплювачі. Знаходить переповнення купи (з точністю до
  байта), use-after-free, подвійне звільнення, витоки; стек і глобальні
  змінні не перевіряються. Тести: `tests/concurrency/run-asan.sh`
  (13 програм × 3 набори опцій, 39/39), `tests/test/tasan1`–`3`;
  інструментовані тести `spans` (35) і `smartptrs` (44) — без звітів.
  Сповільнення тестів `smartptrs` — 2,2×. Посібник —
  `docs/concurrency/guides/asan.md`.
- ThreadSanitizer у рідному генераторі коду (розділ 3.3 дорожньої карти,
  ADR-0010): ключ `-fsanitize=thread` для x86_64-linux, макрос
  `FPC_SANITIZE_THREAD`. Прохід `compiler/x86/tsaninstr.pas` після
  розподілу регістрів вставляє перед кожною інструкцією з операндом-пам'яттю
  виклик трампліна з точним розміром доступу; не інструментуються кадр
  процедури, `threadvar`, GOT, атомарні інструкції й блоки `asm`. Новий
  модуль `fpctsan` (`rtl-objpas`): трампліни, лінкування `libtsan`,
  анотації `TsanRelease`/`TsanAcquire`; компілятор додає його до
  інструментованих модулів, а до програми — `cmem`. Лінкер знаходить теку
  `libtsan` через `gcc -print-file-name`. `cthreads`: у процесі з TSan
  функції pthread беруться з глобальної області символів (перехоплювачі
  TSan), `CDoneCriticalSection` не розблоковує м'ютекс «про всяк випадок».
  `TArc<T>`/`TWeak<T>` анотовано для TSan. Тести:
  `tests/concurrency/run-tsan.sh` (11 програм з навмисними гонками й без,
  × 3 набори опцій, 33/33), `tests/test/ttsan1`–`5`; інструментовані тести
  `spans` (35) і `smartptrs` (44) — без попереджень. Стрес-тести
  `smartptrs` під TSan сповільнюються в 2–3 рази (Helgrind — ~1300×).
  Посібник — `docs/concurrency/guides/tsan.md`.
- `fcl-passrc` і fpdoc: директива `end nocopy` (ADR-0008) розбирається для
  записів, зокрема узагальнених, разом із `deprecated`/`platform`/`align` у
  будь-якому порядку; ознака `TPasRecordType.NoCopy`, виведення в
  `GetDeclaration`, `TPasWriter`, HTML і Markdown-довіднику fpdoc. Раніше
  makeskel/fpdoc/pas2js не розбирали модулі з `end nocopy`, тож генерація
  довідника йшла без `FPC_HAS_NOCOPY_TYPES`; тепер ознаку передано
  (`docs/apidoc.toml`). 12 нових тестів fcl-passrc (2899, 0 падінь).
- Зрізи пам'яті — модуль `spans` (`System.Spans`) у `rtl-objpas` (розділ 3.2
  дорожньої карти): `TSpan<T>`/`TReadOnlySpan<T>` — вікна в статичний чи
  динамічний масив, рядок або `TBytes` без копіювання й алокацій; `Slice`,
  `Chunk` (неперетинне розбиття для паралельних задач), `CopyFrom` з
  перекриттям, `Fill`, `ToArray`, `Overlaps`, `for..in`, `SpanOf`/
  `MutableSpanOf` для рядків. Межі перевіряються завжди (ADR-0009: `-Cr`
  користувача на код дженерика не діє). 35 fpcunit-тестів, зокрема
  паралельні (Helgrind — 0 повідомлень), heaptrc — 0 витоків; посібник
  `guides/spans.md`, fpdoc `rtl-objpas/xml/spans.xml`, приклад
  `examples/spans_parallel.pp`, скрипт `tests/concurrency/build-spans.sh`.
- Компілятор: некопійовані типи — директива `end nocopy;` для записів
  (ADR-0008). Присвоєння зі змінної/поля/елемента/розіменування, параметр
  за значенням і `Copy()` динамічного масиву для такого типу (і типів, що
  його містять) — помилки компіляції; результат функції та `Default()`
  дозволені. Ознака `FPC_HAS_NOCOPY_TYPES`, прапорець `df_nocopy`
  (`ppudump`: «No copy»). `TScoped<T>` і гарди `SyncObjs` оголошено
  `nocopy`; перевірка `AddRef`/`Copy` під час виконання лишається для копій
  поза кодом користувача. Тести `tests/test/tnocopy1`–`27`.
- Компілятор: реалізація дженерик-підпрограми, оголошеної з обмеженнями
  в `interface` чи в записі/класі, може мати в заголовку дженерики, що
  вимагають ці обмеження (`function MakeBox<T>(...): specialize TBox<T>`
  при `TBox<T: class>`). Раніше реалізація не повторює обмежень, і
  заголовок падав з `Class type expected`; тепер такі перевірки
  відкладаються до зіставлення з оголошенням, а без нього повторюються з
  тими самими помилками. Нова ознака `FPC_HAS_CONSTRAINED_GENERIC_FORWARD`.
- `smartptrs`: фабрики `MakeScoped<T: class>`/`MakeArc<T: class>` з
  виведенням типу (`S := MakeScoped(TStringList.Create)`), під
  `FPC_HAS_CONSTRAINED_GENERIC_FORWARD`.
- Розумні вказівники на керованих записах — модуль `smartptrs`
  (`System.SmartPtrs`) у `rtl-objpas` (розділ 3.1 дорожньої карти):
  `TScoped<T>` — одноосібне володіння, `Free` на виході з області видимості
  й під час розкручування винятку, копіювання власника піднімає
  `ESmartPtrError`, передача володіння через `Move`/`Release`/`Reset`;
  `TArc<T>` — спільне володіння будь-яким `TObject` з атомарним лічильником
  і блоком керування; `TWeak<T>` — спостерігач без володіння з атомарним
  `Lock` (без «воскресіння» звільненого об'єкта). 40 fpcunit-тестів
  (`utcsmartptrs.pp`, зокрема стрес-тести на 8 потоках), heaptrc — 0 витоків;
  посібник `guides/smart-pointers.md`, ADR-0007, fpdoc
  `rtl-objpas/xml/smartptrs.xml`, приклад `examples/smart_pointers.pp`,
  скрипт `tests/concurrency/build-smartptrs.sh`.
- Неблокувальний `await` у корутинах: усередині файбера `await`,
  `IFuture.Value`, `ITask.Wait` і `TTask.WaitForAll` без таймауту
  призупиняють файбер замість блокування потоку ОС (`System.Threading`:
  `TaskAwaitHook`, `TaskOnComplete`; `fcl-coroutines` встановлює точку
  підключення для `TFiber`, `TFiber.SuspendOnWait`). Поза файбером і в
  генераторах очікування блокує, як раніше.
- `TFiber.Async<T>` і `TFiber.Spawn`: запуск функції чи процедури як
  корутини з поверненням `IFuture<T>`/`ITask` (синхронно до першого
  очікування, далі — у потоці циклу подій або пулу). Тест: 1000 корутин по
  100 мс очікування на одному потоці завершуються за ~140 мс.
- **Фаза 1.1 (`packages/vcl-compat/src/system.threading.pp`) — неблокувальні продовження задач (`ContinueWith` / `ThenBy`) та кооперативне скасування (`TCancellationToken`):**
  - `TCancellationTokenSource`, `TCancellationToken` та `TCancellationTokenRegistration` —
    легковаговий потокобезпечний механізм кооперативного скасування з підрахунком посилань
    (`ICancellationState`), неблокувальним читанням `IsCancellationRequested`,
    таймаутним скасуванням `CancelAfter` (та конструкторами з `Cardinal` / `TTimeSpan`),
    комбінованими джерелами `CreateLinkedTokenSource`, методом `Reset`, подією
    `WaitHandle` і миттєвими зворотними викликами `Register` / `Unregister`.
  - Підтримка передавання `TCancellationToken` у `TTask.Create`, `TTask.Run`,
    `TTask.Future<T>`, `TParallel.&For` (32-бітні та 64-бітні перевантаження) та
    `TParallel.Join`, а також автоматичне успадкування контекстного токена дочірніми
    задачами та вкладеними циклами від `TTask.CurrentTask`.
  - `ITask.ContinueWith` та `IFuture<T>.ContinueWith` з прапорцями
    `TTaskContinuationOption` / `TTaskContinuationOptions` (`NotOnCompleted`,
    `NotOnFaulted`, `NotOnCanceled`, `OnlyOnCompleted`, `OnlyOnFaulted`,
    `OnlyOnCanceled`, `ExecuteSynchronously`).
  - Типізовані неблокувальні конвеєри `.ThenBy<TResult>` і `.ThenBy<T, TResult>`
    (через `TITaskHelper = type helper for ITask` та `TTask.ThenBy<T, TResult>`) і
    метод `IFuture<T>.Map` із автоматичним прокиданням винятків (`PropagateExceptionFrom`)
    та стану скасування крізь усі етапи конвеєра без блокування потоків пулу.
  - Набір тестів `TTestContinuationsAndCancellation` у `packages/vcl-compat/tests/utthreading.pp`,
    демонстраційна програма `docs/concurrency/examples/continuations_cancel.pp` та ADR-0005.
- **Фаза 2 (`packages/fcl-base/src/syncobjs.pp`) — нові примітиви синхронізації:**
  - `TCountdownEvent` — легковагова синхронізація завершення динамічної кількості
    підзадач (`Signal`, `AddCount`, `TryAddCount`, `Reset`, `WaitFor`,
    `CurrentCount`, `InitialCount`, `IsSet`) з атомарним швидким шляхом та
    анотаціями Valgrind (`VgHappensBefore` / `VgHappensAfter`).
  - `TBarrier` — пофазна циклічна синхронізація групи потоків для ітеративних
    паралельних алгоритмів (`SignalAndWait`, `AddParticipant`, `AddParticipants`,
    `RemoveParticipant`, `RemoveParticipants`, `CurrentPhaseNumber`,
    `ParticipantCount`, `ParticipantsRemaining`) з подвійним буфером подій
    `FPhaseEvents[0..1]`, підтримкою пост-фазної дії `TBarrierPhaseAction` та
    пробросом `EBarrierPostPhaseException` усім учасникам фази.
  - `TSlimReaderWriterLock` та RAII-гарди `TSlimReadLockGuard`,
    `TSlimWriteLockGuard` — швидке блокування читання/запису в просторі
    користувача (lock-free атомарний швидкий шлях `TryAcquireReadFast` /
    `TryAcquireWriteFast`, короткий `TSpinWait`, пріоритет записувачів проти
    голодування `FWaitingWriters` та автоматичне звільнення через `Finalize`).
  - `TCustomChannel` і `generic TChannel<T>` — потокобезпечні обмежені
    (`aCapacity > 0`, із автоматичним backpressure) та необмежені
    (`aCapacity = 0`, із динамічним розширенням кільцевого буфера) канали за
    моделлю CSP у стилі Go (`Send`, `TrySend`, `Receive`, `TryReceive`, `Close`,
    `EChannelClosedException`) та стековий перелічувач `TChannelEnumerator` для
    циклу `for Msg in Channel do` без алокацій у купі.
  - Набір тестів `TTestSyncObjsPhase2` у `packages/vcl-compat/tests/utthreading.pp`,
    демонстраційна програма `docs/concurrency/examples/syncobjs_phase2.pp`,
    посібник `docs/concurrency/guide-syncobjs.md`, ADR-0004 та fpdoc-опис
    `packages/fcl-base/xml/syncobjs-phase2.xml`.
- `docs/concurrency/examples/`: приклади порівняння «класичний TThread vs
  System.Threading» (`primes_*`, `report_*`, `batch_processing.pp`,
  `showcase_pipeline.pp`, `syncobjs_phase2.pp`, `continuations_cancel.pp`) і розділ 10 у PDF.
- `fcl-base/src/fpvalgrind.pp`: клієнтські запити valgrind (happens-before/after,
  clean memory, benign race); анотації в `TSpinLock` і `System.Threading`
  під `-dFPC_VALGRIND`. Див. `docs/concurrency/valgrind.md`.
- `tests/concurrency/build-testcompat-valgrind.sh`, `fpc-helgrind.supp`,
  `hgsummary.py`: збірка й аналіз прогонів helgrind/drd.
- Документація: `docs/concurrency/` (огляд, шаблон ADR, базова лінія тестів).
- `tests/concurrency/fpcenv.sh`: середовище для компіляції тестів свіжозібраним компілятором.
- `tests/concurrency/build-testcompat.sh`: збірка тестів vcl-compat з поточних джерел.
- `tests/concurrency/stress.sh`: стрес-прогін наборів `System.Threading` (N повторів, таймаут).
- **Фаза 1.4 (`packages/fcl-async/` та компілятор `compiler/ppcx64`) — корутини, файбери та async / await:**
  - **Крок 1 (бібліотечний)**: новий пакет `fcl-async` (`packages/fcl-async/`):
    - `TFiber` (`async.fiber.pp`): легковагові стекові корутини (user-space fibers) для System V AMD64 ABI з надшвидким перемиканням контексту на вбудованому асемблері (`FiberSwitchContext`), збереженням і відновленням callee-saved регістрів (`%rbx, %rbp, %r12-%r15`) та покажчика стеку `%rsp` (<10 нс).
    - Гарантоване 16-байтне вирівнювання стеку корутини згідно з System V AMD64 ABI (`%rsp % 16 == 8` на вході в процедуру), що запобігає апаратним аваріям інструкцій SSE/AVX (`movaps`).
    - Динамічна релокація глобальних змінних threadvar винятків FPC (`ExceptAddrStack`, `ExceptObjectStack`) через `FPC_THREADVAR_RELOCATE`, повна симетрична ізоляція стеку винятків для кожного файбера та безпечна міграція файбера між різними потоками ОС.
    - Методи `TFiber.Await<T>(IFuture<T>)` та `TFiber.Await(ITask)` для неблокуючого призупинення корутини без блокування системного потоку ОС, `TFiber.Sleep(ms, loop)` через таймери `fcl-eventloop` та неблокуюче читання/запис сокетів `TFiber.AwaitRead` / `TFiber.AwaitWrite`.
    - `generic TGenerator<T>` (`async.generator.pp`): ледачі генератори послідовностей на базі корутин із зворотним викликом `YieldValue`, повною підтримкою `IEnumerator<T>` / `IEnumerable<T>` та прямим обходом у циклі `for..in`.
    - Фундамент скінченних автоматів (`async.statemachine.pp`): `generic TTaskCompletionSource<TResult>` (`Task`, `SetResult`, `SetException`, `SetCanceled`), `TAsyncTaskMethodBuilder<TResult>` та `TAsyncTaskBuilder` за контрактом C# Roslyn.
    - Модульні тести `packages/fcl-async/tests/utasync.pp` (12 тестів: `TTestFibers`, `TTestGenerators`, `TTestStateMachines`), скрипт `tests/concurrency/build-async.sh`.
  - **Крок 2 (у компіляторі `compiler/ppcx64`)**:
    - Додано процедурний модифікатор/директиву `async` (`pio_async` у `timplprocoption` в `compiler/symconst.pas`, парсер `compiler/pdecsub.pas`) для маркування процедур та функцій.
    - Реалізовано строгу типізаційну перевірку повернення: функції з `async;` зобов'язані повертати `ITask` або `specialize IFuture<T>` (помилка `parser_e_async_must_return_task_or_future` = 03380 у `compiler/pdecsub.pas`, `compiler/msg/errore.msg`).
    - Реалізовано нову директиву компілятора `{$ASYNCMODE AUTO|FIBER|STATEMACHINE}` (`compiler/scandir.pas`, `compiler/fmodule.pas`) з діагностикою помилок `scan_e_illegal_asyncmode` (02123).
    - Інтегровано життєвий цикл стану `asyncinfo` у `tprocinfo.destroy` (`compiler/procinfo.pas`).
    - Додано контекстний оператор `await` (`compiler/pexpr.pas`) для неблокуючого очікування майбутніх задач у виразах (`Val := await Future;` автоматично читає властивість `.Value`) та задачах (`await Task;` викликає `.Wait`) з підключенням `TaskAwaitHook` для файберів.
    - Модуль `packages/fcl-coroutines/src/fclasync.pp`: додано ергономічні методи `RunAsync<T>`, `SpawnAsync` та `AsyncSleep(ms)` для сучасного асинхронного стилю програмування.
    - Створено пакет із 10 порівняльних програм-бенчмарків ModernFreePascal vs C# (.NET) у `tests/concurrency/comparison/` (всі 10/10 тестів успішно пройдено).
    - Збережено 100% сумісність двійкових файлів PPU (`tppuset1` / `tppuset8`) та чинних модулів RTL завдяки контекстному аналізу без додавання зарезервованих слів у загальний лексер.
  - Демонстраційний приклад `docs/concurrency/examples/coroutine_showcase.pp`, посібник користувача `docs/concurrency/guide-async.md`, тестовий набір `tests/concurrency/test_modern_async.pp` та оновлений повний довідник `docs/concurrency/modern-concurrency-reference.md`.
- **Розділ 2.1 (`compiler/ppcx64`) — Виведення типів для узагальнених методів (Generic Type Inference) та необов'язковий `specialize`:**
  - Додано новий перемикач режимів `{$modeswitch implicitgenerics}` (у `globtype.pas`, `scanner.pas`, `ppudump.pp`).
  - У режимі `objfpc` під `{$modeswitch implicitgenerics}` дозволено опускати ключове слово `specialize`:
    - Для узагальнених типів (наприклад, `IFuture<string>`, `TFPGList<Integer>`, `TBox<T>`);
    - Для явних викликів методів і процедур (наприклад, `Identity<string>('hello')`, `TTask.Future<string>(...)`).
  - Реалізовано виведення типів для параметрів узагальнених методів і функцій (Generic Type Inference):
    - Для звичайних значень аргументів (`Identity('hello')`, `TBoxFactory.Wrap(12345)`);
    - Для анонімних функцій (`anonymous functions`) та посилань на функції (`reference to function/procedure`, `is_invokable` інтерфейси), зокрема виведення параметра `<TResult>` із типу повернення функції (`returndef`) та вирівнювання прихованих параметрів (`vo_is_hidden_para`).
    - Підтримка виведення у багатопотокових ланцюжках задач `TTask.Future(function: string begin Result := 'ok'; end)` та `task.ThenBy(...)`.
  - Модульний тестовий набір `tests/concurrency/test_implicit_generics.pp`.
- **Розділ 2.2 (`compiler/ppcx64`) — Короткий синтаксис лямбда-виразів (`=>`):**
  - Додано новий перемикач режимів `{$modeswitch arrowfunctions}` (у `globtype.pas`, `scanner.pas`, `ppudump.pp`), що автоматично активує `anonymousfunctions` та `functionreferences`.
  - Додано токен `_ARROW` (`=>`) та реалізовано підтримку стрілкових функцій у парсері компілятора (`compiler/pexpr.pas`, `compiler/psub.pas`):
    - Безпараметричні лямбди: `() => Expr`;
    - Один аргумент без дужок або з дужками: `I => Stmt`, `(I) => Stmt`;
    - Кілька аргументів із контекстним виведенням типів: `(A, B) => A + B`;
    - Явно типізовані аргументи зі специфікаторами (`const`, `var`, `out`): `(A: Integer, B: Integer) => A + B`;
    - Опціональна явна декларація типу повернення: `(X): Integer => X * 2`;
    - Тіло-вираз (Expression body) з автоприсвоєнням результату для функцій або виконанням дії для процедур, включаючи коректну роботу з керованими типами (`string`, інтерфейси, динамічні масиви);
    - Тіло-блок (Block body): `(I) => begin ... end;`.
  - Повна інтеграція зі збіркою `System.Threading` (`TParallel.&For`, `TTask.Future`), колекціями та подіями зі скороченням шаблонного коду у 2–3 рази.
  - Повний модульний тестовий набір: `tests/concurrency/test_arrow_functions.pp`.
  - Окремий посібник користувача: `docs/concurrency/guide-arrow-functions.md`.
- **Розділ 2.4 (`compiler/ppcx64`) — Кортежі (Tuples) та деконструкція `(A, B) := Func()`:**
  - Додано новий перемикач режимів `{$modeswitch tuples}` (у `globtype.pas`, `scanner.pas`, `ppudump.pp`).
  - Додано опцію `df_tuple` у `tdefoption` (`symconst.pas`, `ppudump.pp`) для розпізнавання записів-кортежів.
  - Реалізовано розбір типів кортежів `parse_tuple_type` у `ptype.pas` для позиційних `(Integer, string)` та іменованих `(Count: Integer, Sum: Int64)` кортежів як анонімних записів на стеку.
  - Реалізовано розбір літералів кортежів `parse_tuple_literal` у `pexpr.pas` з автоматичним виведенням типів (цілі константи типізуються як `s32inttype` / `Integer`, рядки як `AnsiString` / `UnicodeString`).
  - Реалізовано деконструкцію кортежів `tuple_assignment_statement` у `pstatmnt.pas`:
    - Розпакування в наявні змінні: `(A, B) := Expr;`;
    - Розпакування з оголошенням нових локальних змінних: `var (A, B) := Expr;` та `(var A, B) := Expr;`;
    - Одночасний обмін значеннями без додаткової тимчасової змінної: `(X, Y) := (Y, X);` та циклічні зсуви `(A, B, C) := (C, A, B);` з повною безпекою для керованих типів (`string`).
  - Реалізовано доступ до полів кортежів: іменований (`Tup.Count`) та позиційний (`Tup.Item1`, `Tup.Item2`), включаючи зворотний фолбек `ItemN` для іменованих кортежів у `symtable.pas`.
  - Реалізовано структурну еквівалентність та сумісність типів кортежів у `defcmp.pas`: кортежі з однаковою кількістю полів і сумісними типами є взаємозамінними (`T2 := T1`).
  - Повний модульний тестовий набір (24 тести): `tests/concurrency/test_tuples.pp`.
  - Окремий посібник користувача: `docs/concurrency/guide-tuples.md`.

