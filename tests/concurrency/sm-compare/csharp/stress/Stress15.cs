using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

/* 15 await stress tests, paired with pascal/stress15.pp.
   A line is: number, name, await count, milliseconds, checksum, expected, PASS or FAIL. */
sealed class Program
{
    const int ChainN = 100000;
    const int CallsN = 3000;
    const int YieldN = 250;
    const int SeqN = 20;
    const int SeqMs = 15;
    const int ConcN = 1000;
    const int ConcMs = 40;
    const int FanN = 1000;
    const int FanMs = 70;
    const int NestD = 6;
    const int NestR = 150;
    const int FinallyN = 4000;
    const int ExceptN = 250;
    const int StrN = 150;
    const int ContN = 30000;
    const int BreakAtN = 400;
    const int BreakTop = 200000;
    const int ExitAtN = 60;
    const int ExitTop = 20000;
    const int ChildN = 200;
    const int ChildMs = 25;
    const int HammerN = 300;
    const int HammerSteps = 4;

    static int Passed;
    static int Failed;
    static int FinallyCount;
    static readonly Task<int> Done = Task.FromResult(1);
    static Task Shared;
    static Task<int>[] Faults;

    static void Report(string id, string name, int awaits, long t0, long got, long expect)
    {
        double ms = (Stopwatch.GetTimestamp() - t0) * 1000.0 / Stopwatch.Frequency;
        string st;
        if (got == expect)
        {
            Passed++;
            st = "PASS";
        }
        else
        {
            Failed++;
            st = "FAIL";
        }
        Console.WriteLine(id + "\t" + name + "\t" + awaits + "\t" + ms.ToString("F2") + "\t" + got + "\t" + expect + "\t" + st);
        Console.Out.Flush();
    }

    static void BeginTest(string id, string name)
    {
        Console.Error.WriteLine(">> " + id + " " + name);
        Console.Error.Flush();
    }

    static Task<int> Yield1()
    {
        var src = new TaskCompletionSource<int>();
        ThreadPool.QueueUserWorkItem(_ => src.SetResult(1));
        return src.Task;
    }

    static async Task<int> Chain()
    {
        int s = 0;
        for (int i = 1; i <= ChainN; i++)
        {
            int v = await Done;
            s += v;
        }
        return s;
    }

    static async Task<int> Once()
    {
        return await Done;
    }

    static async Task<int> YieldChain()
    {
        int s = 0;
        for (int i = 1; i <= YieldN; i++)
        {
            int v = await Yield1();
            s += v;
        }
        return s;
    }

    static async Task<int> SeqDelay()
    {
        for (int i = 1; i <= SeqN; i++)
            await Task.Delay(SeqMs);
        return SeqN;
    }

    static async Task<int> ConcOne()
    {
        await Task.Delay(ConcMs);
        return 1;
    }

    static async Task<int> FanOne()
    {
        await Shared;
        return 1;
    }

    static async Task<int> Depth(int n)
    {
        if (n == 0)
            return await Done;
        int v = await Depth(n - 1);
        return v;
    }

    static async Task<int> FinallyLoop()
    {
        for (int i = 1; i <= FinallyN; i++)
        {
            try
            {
                await Done;
            }
            finally
            {
                FinallyCount++;
            }
        }
        return FinallyCount;
    }

    static async Task<int> CatchLoop()
    {
        int s = 0;
        for (int i = 0; i < ExceptN; i++)
        {
            try
            {
                await Faults[i];
            }
            catch
            {
                s++;
            }
        }
        return s;
    }

    static async Task<int> Grow()
    {
        string s = "";
        for (int i = 1; i <= StrN; i++)
        {
            await Yield1();
            s = s + "x";
        }
        return s.Length;
    }

    static async Task<long> ContinueSum()
    {
        long s = 0;
        for (int i = 1; i <= ContN; i++)
        {
            if (i % 3 == 0)
                continue;
            await Done;
            s += i;
        }
        return s;
    }

    static async Task<int> BreakEarly()
    {
        int s = 0;
        for (int i = 1; i <= BreakTop; i++)
        {
            await Done;
            s = i;
            if (i == BreakAtN)
                break;
        }
        return s;
    }

    static async Task<int> ExitEarly()
    {
        for (int i = 1; i <= ExitTop; i++)
        {
            await Done;
            if (i == ExitAtN)
                return i;
        }
        return -1;
    }

    static async Task<int> Child(int n)
    {
        await Task.Delay(ChildMs);
        return n;
    }

    static async Task<int> Parent()
    {
        var kids = new Task<int>[ChildN];
        for (int i = 0; i < ChildN; i++)
            kids[i] = Child(i + 1);
        int s = 0;
        for (int i = 0; i < ChildN; i++)
        {
            int v = await kids[i];
            s += v;
        }
        return s;
    }

    static async Task<int> Hammer()
    {
        int s = 0;
        for (int i = 1; i <= HammerSteps; i++)
        {
            int v = await Yield1();
            s += v;
        }
        return s;
    }

    static long ExpectedContinue()
    {
        long s = 0;
        for (int i = 1; i <= ContN; i++)
            if (i % 3 != 0)
                s += i;
        return s;
    }

    static void PrepareFaults()
    {
        Faults = new Task<int>[ExceptN];
        for (int i = 0; i < ExceptN; i++)
        {
            var src = new TaskCompletionSource<int>();
            src.SetException(new Exception("x"));
            Faults[i] = src.Task;
        }
    }

    static long SumTasks(Task<int>[] futs)
    {
        long s = 0;
        for (int i = 0; i < futs.Length; i++)
            s += futs[i].Result;
        return s;
    }

    static async Task<int> Main()
    {
        PrepareFaults();
        int warm = await Once();
        if (warm != 1)
            return 2;
        await Task.Delay(1);
        Console.WriteLine("# sm-stress csharp");
        Console.WriteLine("# threads=" + Environment.ProcessorCount + " freq=" + Stopwatch.Frequency);
        Console.Out.Flush();

        BeginTest("01", "chain_completed");
        long t0 = Stopwatch.GetTimestamp();
        long got = await Chain();
        Report("01", "chain_completed", ChainN, t0, got, ChainN);

        BeginTest("02", "calls_completed");
        t0 = Stopwatch.GetTimestamp();
        got = 0;
        for (int i = 1; i <= CallsN; i++)
            got += await Once();
        Report("02", "calls_completed", CallsN, t0, got, CallsN);

        BeginTest("03", "yield_sequential");
        t0 = Stopwatch.GetTimestamp();
        got = await YieldChain();
        Report("03", "yield_sequential", YieldN, t0, got, YieldN);

        BeginTest("04", "delay_sequential");
        t0 = Stopwatch.GetTimestamp();
        got = await SeqDelay();
        Report("04", "delay_sequential", SeqN, t0, got, SeqN);

        BeginTest("05", "delay_concurrent");
        var futs = new Task<int>[ConcN];
        t0 = Stopwatch.GetTimestamp();
        for (int i = 0; i < ConcN; i++)
            futs[i] = ConcOne();
        await Task.WhenAll(futs);
        got = SumTasks(futs);
        Report("05", "delay_concurrent", ConcN, t0, got, ConcN);

        BeginTest("06", "fanout_one_delay");
        futs = new Task<int>[FanN];
        t0 = Stopwatch.GetTimestamp();
        Shared = Task.Delay(FanMs);
        for (int i = 0; i < FanN; i++)
            futs[i] = FanOne();
        await Task.WhenAll(futs);
        got = SumTasks(futs);
        Report("06", "fanout_one_delay", FanN, t0, got, FanN);

        BeginTest("07", "nested_calls");
        t0 = Stopwatch.GetTimestamp();
        got = 0;
        for (int i = 1; i <= NestR; i++)
            got += await Depth(NestD);
        Report("07", "nested_calls", NestR * NestD, t0, got, NestR);

        BeginTest("08", "finally_loop");
        FinallyCount = 0;
        t0 = Stopwatch.GetTimestamp();
        got = await FinallyLoop();
        Report("08", "finally_loop", FinallyN, t0, got, FinallyN);

        BeginTest("09", "faulted_loop");
        t0 = Stopwatch.GetTimestamp();
        got = await CatchLoop();
        Report("09", "faulted_loop", ExceptN, t0, got, ExceptN);

        BeginTest("10", "string_across_yield");
        t0 = Stopwatch.GetTimestamp();
        got = await Grow();
        Report("10", "string_across_yield", StrN, t0, got, StrN);

        BeginTest("11", "continue_loop");
        t0 = Stopwatch.GetTimestamp();
        got = await ContinueSum();
        Report("11", "continue_loop", ContN - (ContN / 3), t0, got, ExpectedContinue());

        BeginTest("12", "break_early");
        t0 = Stopwatch.GetTimestamp();
        got = await BreakEarly();
        Report("12", "break_early", BreakAtN, t0, got, BreakAtN);

        BeginTest("13", "exit_early");
        t0 = Stopwatch.GetTimestamp();
        got = await ExitEarly();
        Report("13", "exit_early", ExitAtN, t0, got, ExitAtN);

        BeginTest("14", "parent_awaits_children");
        t0 = Stopwatch.GetTimestamp();
        got = await Parent();
        Report("14", "parent_awaits_children", ChildN * 2, t0, got, (long)ChildN * (ChildN + 1) / 2);

        BeginTest("15", "hammer_yield");
        futs = new Task<int>[HammerN];
        t0 = Stopwatch.GetTimestamp();
        for (int i = 0; i < HammerN; i++)
            futs[i] = Hammer();
        await Task.WhenAll(futs);
        got = SumTasks(futs);
        Report("15", "hammer_yield", HammerN * HammerSteps, t0, got, (long)HammerN * HammerSteps);

        Console.WriteLine("PASSED " + Passed + "/15");
        return Failed == 0 ? 0 : 1;
    }
}
