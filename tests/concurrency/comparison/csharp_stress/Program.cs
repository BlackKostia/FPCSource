using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

namespace Stress500;

class Program
{
    static int TotalPassed = 0;
    static int TotalFailed = 0;
    static int CategoryPassed = 0;
    static int CategoryFailed = 0;
    static int CleanupCounter = 0;

    static void Check(string desc, bool ok)
    {
        if (ok)
        {
            Interlocked.Increment(ref TotalPassed);
            Interlocked.Increment(ref CategoryPassed);
        }
        else
        {
            Interlocked.Increment(ref TotalFailed);
            Interlocked.Increment(ref CategoryFailed);
            Console.WriteLine($"  [FAIL] {desc}");
        }
    }

    static void StartCategory(string name)
    {
        CategoryPassed = 0;
        CategoryFailed = 0;
        Console.WriteLine($"--- [Category] {name} ---");
    }

    static void EndCategory(string name, long elapsedMs)
    {
        Console.WriteLine($"    Result: {CategoryPassed}/50 passed ({CategoryFailed} failed) in {elapsedMs} ms");
    }

    // =========================================================================
    // Category 1: Deep Recursion & Call-Chaining (Tests 1..50)
    // =========================================================================
    static async Task<long> RecursiveSumAsync(int n)
    {
        if (n <= 1) return n;
        long sub = await RecursiveSumAsync(n - 1);
        return n + sub;
    }

    static async Task RunCategory1()
    {
        StartCategory("1. Deep Recursion & Call-Chaining (50 tests)");
        var sw = Stopwatch.StartNew();

        for (int i = 1; i <= 50; i++)
        {
            int depth = i * 4;
            long expected = (long)depth * (depth + 1) / 2;
            long actual = await RecursiveSumAsync(depth);
            Check($"Test {i}: Recursion depth {depth}", actual == expected);
        }

        sw.Stop();
        EndCategory("1. Deep Recursion", sw.ElapsedMilliseconds);
    }

    // =========================================================================
    // Category 2: Massive Fan-Out & Fan-In (WhenAll) (Tests 51..100)
    // =========================================================================
    static async Task<int> WorkerTaskAsync(int id, int multiplier)
    {
        await Task.Delay(1);
        return id * multiplier;
    }

    static async Task RunCategory2()
    {
        StartCategory("2. Massive Fan-Out & Fan-In (WhenAll) (50 tests)");
        var sw = Stopwatch.StartNew();

        for (int i = 1; i <= 50; i++)
        {
            int taskCount = 5 + (i * 5);
            var tasks = new Task<int>[taskCount];
            int expected = 0;

            for (int j = 0; j < taskCount; j++)
            {
                tasks[j] = WorkerTaskAsync(j + 1, 2);
                expected += (j + 1) * 2;
            }

            int[] results = await Task.WhenAll(tasks);
            int sum = 0;
            for (int j = 0; j < taskCount; j++) sum += results[j];

            Check($"Test {50 + i}: Fan-Out WhenAll({taskCount} tasks)", sum == expected);
        }

        sw.Stop();
        EndCategory("2. Massive Fan-Out & Fan-In", sw.ElapsedMilliseconds);
    }

    // =========================================================================
    // Category 3: Fast-Path Synchronous Awaits (Tests 101..150)
    // =========================================================================
    static Task<int> FastValueAsync(int v)
    {
        return Task.FromResult(v);
    }

    static async Task<long> FastSumAsync(int count)
    {
        long s = 0;
        for (int k = 1; k <= count; k++)
        {
            s += await FastValueAsync(k);
        }
        return s;
    }

    static async Task RunCategory3()
    {
        StartCategory("3. Fast-Path Synchronous Awaits (50 tests)");
        var sw = Stopwatch.StartNew();

        for (int i = 1; i <= 50; i++)
        {
            int n = i * 50;
            long expected = (long)n * (n + 1) / 2;
            long actual = await FastSumAsync(n);
            Check($"Test {100 + i}: Fast-path {n} awaits", actual == expected);
        }

        sw.Stop();
        EndCategory("3. Fast-Path Synchronous Awaits", sw.ElapsedMilliseconds);
    }

    // =========================================================================
    // Category 4: First-Finisher Racing (WhenAny) (Tests 151..200)
    // =========================================================================
    static async Task<int> DelayTaskAsync(int id, int delayMs)
    {
        await Task.Delay(delayMs);
        return id;
    }

    static async Task<int> RaceWinnerAsync()
    {
        var f0 = DelayTaskAsync(100, 20);
        var f1 = DelayTaskAsync(200, 1); // Fastest!
        var f2 = DelayTaskAsync(300, 25);
        var f3 = DelayTaskAsync(400, 30);

        var winner = await Task.WhenAny(f0, f1, f2, f3);
        if (winner == f1)
            return await f1;
        return -1;
    }

    static async Task RunCategory4()
    {
        StartCategory("4. First-Finisher Racing (WhenAny) (50 tests)");
        var sw = Stopwatch.StartNew();

        for (int i = 1; i <= 50; i++)
        {
            int winnerId = await RaceWinnerAsync();
            Check($"Test {150 + i}: WhenAny winner is fastest", winnerId == 200);
        }

        sw.Stop();
        EndCategory("4. First-Finisher Racing", sw.ElapsedMilliseconds);
    }

    // =========================================================================
    // Category 5: Cooperative Cancellation (CancellationToken) (Tests 201..250)
    // =========================================================================
    static async Task<int> CancellableAsync(CancellationToken token, int delayMs)
    {
        await Task.Delay(delayMs, token);
        return 777;
    }

    static async Task RunCategory5()
    {
        StartCategory("5. Cooperative Cancellation (CancellationToken) (50 tests)");
        var sw = Stopwatch.StartNew();

        for (int i = 1; i <= 50; i++)
        {
            using var cts = new CancellationTokenSource();
            bool caught = false;
            Task<int> task;

            if (i <= 15)
            {
                cts.Cancel();
                task = CancellableAsync(cts.Token, 500);
            }
            else
            {
                task = CancellableAsync(cts.Token, 500);
                Thread.Sleep(2);
                cts.Cancel();
            }

            try
            {
                await task;
            }
            catch (OperationCanceledException)
            {
                caught = true;
            }

            Check($"Test {200 + i}: Cancellation caught and status Canceled",
                caught && task.IsCanceled);
        }

        sw.Stop();
        EndCategory("5. Cooperative Cancellation", sw.ElapsedMilliseconds);
    }

    // =========================================================================
    // Category 6: Exception Propagation & Handling (Tests 251..300)
    // =========================================================================
    static async Task<int> FaultingChainAsync(int depth)
    {
        if (depth <= 0)
            throw new InvalidOperationException("Intentional failure");
        int sub = await FaultingChainAsync(depth - 1);
        return sub + 1;
    }

    static async Task<int> RecoveringAsync(int depth)
    {
        try
        {
            return await FaultingChainAsync(depth);
        }
        catch (Exception)
        {
            return 999;
        }
    }

    static async Task RunCategory6()
    {
        StartCategory("6. Exception Propagation & Handling (50 tests)");
        var sw = Stopwatch.StartNew();

        for (int i = 1; i <= 50; i++)
        {
            if ((i % 2) == 1)
            {
                bool caught = false;
                try
                {
                    await FaultingChainAsync(i % 10);
                }
                catch (Exception ex)
                {
                    caught = ex.Message.Contains("Intentional failure");
                }
                Check($"Test {250 + i}: Exception propagated through {i % 10} frames", caught);
            }
            else
            {
                int val = await RecoveringAsync(i % 10);
                Check($"Test {250 + i}: Exception recovered with fallback", val == 999);
            }
        }

        sw.Stop();
        EndCategory("6. Exception Propagation & Handling", sw.ElapsedMilliseconds);
    }

    // =========================================================================
    // Category 7: Deterministic Cleanup (try ... finally) (Tests 301..350)
    // =========================================================================
    static async Task<int> ResourceCleaningAsync(bool fail)
    {
        Interlocked.Increment(ref CleanupCounter);
        try
        {
            await Task.Delay(1);
            if (fail) throw new InvalidOperationException("Resource error");
            return 123;
        }
        finally
        {
            Interlocked.Decrement(ref CleanupCounter);
        }
    }

    static async Task RunCategory7()
    {
        StartCategory("7. Deterministic Cleanup (try ... finally) (50 tests)");
        var sw = Stopwatch.StartNew();

        for (int i = 1; i <= 50; i++)
        {
            try
            {
                await ResourceCleaningAsync((i % 2) == 0);
            }
            catch
            {
                // ignore
            }
            Check($"Test {300 + i}: Finally block executed (counter balanced)", CleanupCounter == 0);
        }

        sw.Stop();
        EndCategory("7. Deterministic Cleanup", sw.ElapsedMilliseconds);
    }

    // =========================================================================
    // Category 8: Complex Control Flow & Expressions (Tests 351..400)
    // =========================================================================
    static async Task<bool> BoolConditionAsync(int stepsLeft)
    {
        await Task.Delay(1);
        return stepsLeft > 0;
    }

    static async Task<int> ComplexFlowAsync(int count)
    {
        int accum = 0;
        int steps = count;
        while (await BoolConditionAsync(steps))
        {
            accum += (await FastValueAsync(2)) + (await FastValueAsync(3));
            steps--;
        }
        return accum;
    }

    static async Task RunCategory8()
    {
        StartCategory("8. Complex Control Flow & Expressions (50 tests)");
        var sw = Stopwatch.StartNew();

        for (int i = 1; i <= 50; i++)
        {
            int n = (i % 5) + 1;
            int expected = n * 5;
            int actual = await ComplexFlowAsync(n);
            Check($"Test {350 + i}: while await Condition() with {n} steps", actual == expected);
        }

        sw.Stop();
        EndCategory("8. Complex Control Flow & Expressions", sw.ElapsedMilliseconds);
    }

    // =========================================================================
    // Category 9: State Preservation Across Thread Hopping (Tests 401..450)
    // =========================================================================
    static async Task<int> StateMutationAsync(int initialVal, int stepCount)
    {
        int currentVal = initialVal;
        string s = "State:";
        for (int k = 1; k <= stepCount; k++)
        {
            await Task.Delay(1);
            currentVal += k;
            s += k + ",";
        }
        if (s.Length > 6) return currentVal;
        return -1;
    }

    static async Task RunCategory9()
    {
        StartCategory("9. State Preservation Across Thread Hopping (50 tests)");
        var sw = Stopwatch.StartNew();

        for (int i = 1; i <= 50; i++)
        {
            int steps = (i % 4) + 1;
            int expected = 100;
            for (int k = 1; k <= steps; k++) expected += k;

            int actual = await StateMutationAsync(100, steps);
            Check($"Test {400 + i}: Preserved mutated locals across {steps} thread hops", actual == expected);
        }

        sw.Stop();
        EndCategory("9. State Preservation Across Thread Hopping", sw.ElapsedMilliseconds);
    }

    // =========================================================================
    // Category 10: Multi-threaded Reentrancy & Sustained Concurrency (Tests 451..500)
    // =========================================================================
    static async Task<int> ComputeSquareAsync(int v)
    {
        await Task.Delay(1);
        return v * v;
    }

    static async Task RunCategory10()
    {
        StartCategory("10. Multi-threaded Reentrancy & Sustained Concurrency (50 tests)");
        var sw = Stopwatch.StartNew();

        for (int i = 1; i <= 50; i++)
        {
            int concurrentCallers = 16;
            var tasks = new Task<int>[concurrentCallers];

            for (int j = 0; j < concurrentCallers; j++)
            {
                tasks[j] = ComputeSquareAsync(j + 1);
            }

            int[] results = await Task.WhenAll(tasks);

            bool allCorrect = true;
            for (int j = 0; j < concurrentCallers; j++)
            {
                if (results[j] != (j + 1) * (j + 1))
                    allCorrect = false;
            }

            Check($"Test {450 + i}: 16 concurrent reentrant callers", allCorrect);
        }

        sw.Stop();
        EndCategory("10. Multi-threaded Reentrancy", sw.ElapsedMilliseconds);
    }

    // =========================================================================
    // Main Entry Point
    // =========================================================================
    static async Task<int> Main(string[] args)
    {
        Console.WriteLine("===============================================================================");
        Console.WriteLine("   MICROSOFT .NET 8 (C#): 500 STRESS TESTS SUITE FOR ASYNC / AWAIT");
        Console.WriteLine("===============================================================================");
        var totalSw = Stopwatch.StartNew();

        await RunCategory1();
        await RunCategory2();
        await RunCategory3();
        await RunCategory4();
        await RunCategory5();
        await RunCategory6();
        await RunCategory7();
        await RunCategory8();
        await RunCategory9();
        await RunCategory10();

        totalSw.Stop();
        Console.WriteLine("===============================================================================");
        Console.WriteLine($"TOTAL: {TotalPassed} / 500 PASSED, {TotalFailed} FAILED in {totalSw.ElapsedMilliseconds} ms");
        Console.WriteLine("===============================================================================");

        return TotalFailed > 0 ? 1 : 0;
    }
}
