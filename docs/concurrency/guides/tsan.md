# Посібник користувача: ThreadSanitizer (`-fsanitize=thread`)

Розділ 3.3 дорожньої карти ([roadmap.md](../roadmap.md)), рішення —
[ADR-0010](../adr/0010-tsan.md). Платформа: **x86_64-linux**, рідний
генератор коду FPC.

## 1. Що це

ThreadSanitizer (TSan) — детектор гонок даних із GCC/Clang. Компілятор
вставляє перед кожним доступом до пам'яті виклик бібліотеки `libtsan`, яка
веде «тіньову» пам'ять і бачить синхронізацію (м'ютекси, умовні змінні,
створення й очікування потоків) через перехоплення pthread. Гонка — два
доступи різних потоків до тієї самої пам'яті, хоча б один запис, без
зв'язку «відбулося раніше» — повідомляється з файлом і рядком:

```
WARNING: ThreadSanitizer: data race (pid=3267566)
  Read of size 4 at 0x00000049f1e0 by thread T2:
    #0 WORKER race_global.pp:12

  Previous write of size 4 at 0x00000049f1e0 by thread T1:
    #0 WORKER race_global.pp:12

  Location is global 'U_$P$RACE_GLOBAL_$$_COUNTER' of size 4
```

Порівняно з Valgrind Helgrind (`fpvalgrind`): той самий стрес-тест
`TTestArcStress.TestConcurrentLastRelease` — 0,2 с без інструментів,
**0,56 с під TSan**, 4 хв 22 с під Helgrind; `TestLockRacesWithRelease`
під TSan — 0,21 с, під Helgrind не завершився за 50 хв.

## 2. Використання

```sh
fpc -fsanitize=thread -gw myprog.pp
setarch $(uname -m) -R ./myprog
```

- `-fsanitize=thread` інструментує модулі, що компілюються з цим ключем, і
  визначає макрос `FPC_SANITIZE_THREAD`. До кожного такого модуля
  компілятор додає модуль `fpctsan` (трампліни, лінкування `libtsan`), а до
  програми — `cmem` (див. нижче).
- `-gw` (або `-gl`) — щоб у звітах були імена процедур, файли й рядки; без
  налагоджувальної інформації FPC видаляє символи під час лінкування, і
  звіти показують лише адреси.
- **`setarch -R`**: TSan із GCC 13 несумісний із високою ентропією ASLR
  сучасних ядер Linux (`vm.mmap_rnd_bits=32`) і завершується з
  `FATAL: ThreadSanitizer: unexpected memory mapping`. Обхід без root —
  запуск із вимкненою рандомізацією адрес; з root — `sysctl
  vm.mmap_rnd_bits=28`.
- Потрібна бібліотека `libtsan` (пакет `libgcc-13-dev`/`gcc`): лінкер сам
  знаходить її теку через `gcc -print-file-name=libtsan.so`.
- `TSAN_OPTIONS` — налаштування під час виконання, напр.
  `exitcode=66 halt_on_error=0 history_size=4`.

## 3. Що інструментується

Після розподілу регістрів і оптимізатора, на остаточних інструкціях, тож
охоплено всі доступи до пам'яті, які генерує компілятор (поля об'єктів,
елементи масивів, глобальні змінні, розіменування, SSE/AVX/x87, операнди
арифметики з пам'яттю). Розмір доступу береться з інструкції (1, 2, 4, 8,
16 байтів або діапазон), тож записи в різні байти одного слова гонкою не
вважаються.

Не інструментується:
- доступи відносно `RSP`/`RBP` — власний кадр процедури (локальні змінні);
- `threadvar` (сегмент `fs:`) і завантаження з GOT;
- атомарні інструкції (`lock`, `xacquire`/`xrelease`, `xchg` з пам'яттю);
- цілі `call`/`jmp`, `lea`, `prefetch`, `clflush`;
- рядкові інструкції (`rep movs` тощо) — без явного операнда-пам'яті;
- блоки `asm` і процедури `assembler`;
- **RTL і пакети**, зібрані без ключа. Щоб перевірити бібліотечний код,
  скомпілюйте його з джерел із `-fsanitize=thread` (як `spans`/`smartptrs`
  у тестах).

## 4. Синхронізація, яку TSan бачить і не бачить

Бачить (через перехоплення pthread у `libtsan`): `TCriticalSection`,
`TEvent`, `RTLEvent*`, `BeginThread`/`WaitForThreadTerminate`, `TThread`,
`malloc`/`free`. Примітиви, частково побудовані на атомарних операціях
(напр. `TMultiReadExclusiveWriteSynchronizer`, `TSpinLock`), можуть давати
хибні звіти — див. нижче.
Для цього `cthreads` під TSan бере функції pthread через глобальний пошук
символів (інакше перехоплювачі оминаються) — див. ADR-0010.

**Не бачить атомарні операції RTL** (`InterlockedIncrement`,
`InterlockedCompareExchange`, `AtomicXxx`): RTL не інструментовано, тож
синхронізація лише через них виглядає для TSan як гонка. Анотуйте такі
місця (модуль `fpctsan` компілятор додає автоматично):

```pascal
{$IFDEF FPC_SANITIZE_THREAD}
TsanRelease(@Block^.Count);     // усе до цього рядка...
{$ENDIF}
if InterlockedDecrement(Block^.Count) = 0 then
begin
  {$IFDEF FPC_SANITIZE_THREAD}
  TsanAcquire(@Block^.Count);   // ...відбулося раніше за все після
  {$ENDIF}
  Dispose(Block);
end;
```

Так анотовано `TArc<T>`/`TWeak<T>` (`smartptrs`). Без анотацій
інструментовані тести `smartptrs` давали 7 хибних гонок, з ними — 0.

## 5. Пам'ять: `cmem`

Менеджер пам'яті FPC повторно використовує звільнені блоки в інших
потоках через атомарні операції, яких TSan не бачить, — це дало б хибні
гонки між старим і новим вмістом блоку. Тому для програм з
`-fsanitize=thread` компілятор додає `cmem` (C `malloc`, який TSan
перехоплює), як для Valgrind і ASan.

## 6. Обмеження

- Лише x86_64-linux, рідний генератор коду (не LLVM-бекенд).
- Стек у звіті має один кадр (функцію доступу): виклики
  `__tsan_func_entry/exit` не вставляються (винятки FPC залишали б
  незбалансований тіньовий стек). Місце доступу (файл:рядок) точне.
- Трампліни зберігають усі цілочислові регістри, прапорці й
  `xmm0..xmm15`, але не старші половини `ymm`/`zmm` і не стек x87:
  `libtsan` (C) їх не використовує, але гарантії ABI для цього немає.
- Модуль, що компілюється з тієї самої теки, де лежить `fpctsan.pp`
  (`packages/rtl-objpas/src/inc`), з `-fsanitize=thread` не збирається:
  неявно доданий `fpctsan` має бути готовим `.ppu`. Компілюйте з копії.
- `libtsan` з GCC 13 вимагає `setarch -R` на ядрах з `mmap_rnd_bits=32`.

## 7. Тести

```sh
tests/concurrency/run-tsan.sh            # 11 програм × (-O-, -O2, -O2 -Cg)
```

Для кожної програми з `tests/concurrency/tsan/` скрипт збирає еталон без
санітайзера й інструментовану версію, запускає її під `setarch -R` і
перевіряє: вивід не змінився (трампліни не псують регістри, прапорці,
SSE/x87); для `EXPECT: race` — є звіт, що вказує на кожен рядок `{RACE}`;
для `EXPECT: norace` — звітів немає. Серед них — перевірка точності
розміру (`race_overlapping_sizes` / `norace_disjoint_sizes`), `threadvar`,
м'ютекс, подія, `join`. Компіляцію (включно з `-Cg` і AVX2) перевіряють
`tests/test/ttsan1`–`5` у штатному наборі.
