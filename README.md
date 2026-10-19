# ModernFreePascal (MFPC)

> **ModernFreePascal (MFPC) is a modern fork of the Free Pascal Compiler with advanced concurrency, coroutines, and ergonomics.**

---

## Mission & Vision

The primary mission of the **ModernFreePascal (MFPC)** project is to revitalize and popularize the Pascal programming language in 21st-century software development. 

Over decades, Pascal has earned a legendary reputation for rock-solid reliability, readable structured syntax, and blazing-fast native compilation without the heavyweight overhead or unpredictable latency of garbage collectors. However, contemporary development demands modern concurrency patterns, expressive syntax, and asynchronous scalability.

MFPC brings Pascal to parity with—and positions it as a competitive native alternative to—modern languages such as **Rust, Go, C# / .NET, and modern C++**, while fully retaining Pascal's foundational advantages:
- **Instant native compilation** directly to optimized machine code.
- **Zero garbage collection (GC) pauses** and predictable memory consumption.
- **Strict, robust static type safety** with modern type inference.
- **Unrivaled cross-platform reach** across architectures (x86_64, AArch64, RISC-V, etc.) and operating systems.
- **Clean, self-documenting syntax**.

---

## Key Modern Features

### 1. Modern Language Ergonomics & Syntax
- **Tuples & Multi-Value Deconstruction (`{$modeswitch tuples}`)**:
  - Positional tuples: `(Integer, string)`
  - Named tuples: `(Count: Integer, Sum: Int64)`
  - Tuple literals: `(A div B, A mod B)`, `('Result', 42)`
  - Deconstruction: `(Quot, Rem) := DivMod(17, 5);`
  - Inline declaration deconstruction: `var (Quot, Rem) := DivMod(17, 5);`
  - Zero-temp-variable parallel swap: `(X, Y) := (Y, X);`
- **Short Lambda / Arrow Functions (`{$modeswitch arrowfunctions}`)**:
  - Concise syntax: `TParallel.&For(0, N - 1, I => ProcessItem(I));`
  - Contextual parameter and return type inference.
  - Multi-argument and block expressions: `(A, B) => begin Log(A); Result := A + B; end;`
- **Generic Method Type Inference & Implicit Generics (`{$modeswitch implicitgenerics}`)**:
  - Optional `specialize` keyword in `objfpc` mode for types and calls.
  - Automatic inference of generic type parameters `<T>` from arguments and anonymous functions:
    ```pascal
    R := TTask.Future(() => ComputeResult(42)); // Automatically infers IFuture<Integer>
    ```

### 2. High-Performance Concurrency & Asynchrony
- **`System.Threading` & Task Parallel Library**:
  - Work-stealing `TThreadPool`, `ITask`, `IFuture<T>`, and `TParallel.For`.
  - Non-blocking pipeline continuations: `.ContinueWith(...)` and `.ThenBy(...)`.
  - Cooperative cancellation trees via `TCancellationToken` and `TCancellationTokenSource`.
- **Next-Gen Synchronization Primitives (`SyncObjs`)**:
  - **`TCountdownEvent`**: Lightweight synchronization for dynamic sub-tasks.
  - **`TBarrier`**: Phased multi-thread synchronization for iterative parallel algorithms.
  - **`TSlimReaderWriterLock`**: High-performance user-space reader/writer lock with RAII scope guards.
  - **`TChannel<T>`**: Go-style Communicating Sequential Processes (CSP) channels with bounded/unbounded buffers and `for Msg in Channel do` iteration.
- **Scalable Asynchronous I/O (`fcl-eventloop`)**:
  - Unified cross-platform event loop leveraging native OS multiplexers:
    - **Linux**: `io_uring` / `epoll`
    - **FreeBSD / macOS**: `kqueue`
    - **Windows**: `IOCP`
  - Capable of sustaining 100,000+ concurrent connections on a multi-threaded worker pool.
- **Coroutines & `async` / `await` (`fcl-coroutines`)**:
  - Stackful fibers (`TFiber`) for AMD64 / POSIX.
  - Generators (`TGenerator<T>`) supporting idiomatic `for Item in Generator do`.
  - `await` operator: inside a coroutine started with `TFiber.Async`/`TFiber.Spawn` it suspends the coroutine without blocking the OS thread (outside coroutines it waits in place). The `async` directive is parsed but does not change code generation yet.

---

## Repository Structure

- `compiler/`: Sources of the ModernFreePascal compiler (GPL v2).
- `rtl/`: Run-Time Library sources (Modified LGPL with linking exception).
- `packages/`: Standard and extended packages:
  - `packages/vcl-compat/`: `System.Threading` implementation.
  - `packages/fcl-base/`: Core classes, synchronization primitives in `syncobjs.pp`.
  - `packages/fcl-eventloop/`: High-performance asynchronous event loop.
  - `packages/fcl-coroutines/`: Coroutines, fibers, generators and async state machines.
- `docs/concurrency/`: Detailed architectural documentation, user guides, and roadmaps:
  - [`guide-tuples.md`](docs/concurrency/guide-tuples.md): Tuples & deconstruction reference.
  - [`guide-arrow-functions.md`](docs/concurrency/guide-arrow-functions.md): Arrow functions reference.
  - [`guide-system-threading.md`](docs/concurrency/guide-system-threading.md): `System.Threading` guide.
  - [`guide-syncobjs.md`](docs/concurrency/guide-syncobjs.md): Synchronization primitives guide.
  - [`guide-eventloop.md`](docs/concurrency/guide-eventloop.md): Asynchronous I/O event loop guide.
  - [`roadmap-improvements.md`](docs/concurrency/roadmap-improvements.md): Long-term development roadmap.
- `tests/`: Extensive compiler and runtime test suite (including `tests/concurrency/`).
- `utils/`: Utilities and tools distributed with the compiler.

---

## Building the Compiler

To build the ModernFreePascal compiler from source:

```bash
# Full bootstrap compiler cycle:
make -C compiler cycle PP=<path-to-bootstrap-ppcx64> -j$(nproc)

# Quick compiler rebuild during development:
make -C compiler compiler FPC=<path-to-bootstrap-ppcx64>
```

To run the modern concurrency and language test suite:
```bash
./compiler/ppcx64 tests/concurrency/test_tuples.pp
./tests/concurrency/test_tuples

./compiler/ppcx64 tests/concurrency/test_arrow_functions.pp
./tests/concurrency/test_arrow_functions
```

---

## Licensing & Acknowledgments

ModernFreePascal is open-source software built upon the monumental foundation created by the **Free Pascal Development Team**:
- **Compiler**: Distributed under the terms of the **GNU General Public License (GPL) version 2** or later. See `LICENSE`.
- **Run-Time Library & Packages**: Distributed under the **GNU Library General Public License (LGPL) version 2** with the **FPC modified linking exception**, permitting the linking of proprietary or third-party independent modules into your executables without requiring source release of those modules.

See the `LICENSE` and `rtl/COPYING.txt` files for full licensing terms.
