using System;
using System.Diagnostics;
using System.Threading.Tasks;

/* 20 checks of async/await, paired with pascal/sm20.pp.
   A line is: number, name, milliseconds, PASS or FAIL. */
sealed class Program
{
    static int Passed;
    static int Failed;
    static int FinallyFlag;
    static readonly Task<int> Done = Task.FromResult(1);
    static readonly Task DoneTask = Task.CompletedTask;

    static void Line(string id, string name, long ms, bool ok)
    {
        if (ok)
        {
            Passed++;
            Console.WriteLine(id + "\t" + name + "\t" + ms + "\tPASS");
        }
        else
        {
            Failed++;
            Console.WriteLine(id + "\t" + name + "\t" + ms + "\tFAIL");
        }
    }

    static long Now()
    {
        return Stopwatch.GetTimestamp();
    }

    static long Elapsed(long t0)
    {
        return (Now() - t0) * 1000 / Stopwatch.Frequency;
    }

#pragma warning disable CS1998
    static async Task<int> SyncOne()
    {
        return 1;
    }

    static async Task<int> Pipeline()
    {
        int n = 1;
        await Task.Delay(100);
        n = n + 1;
        await Task.Delay(100);
        return n + 40;
    }

    static async Task<int> Take(Task<int> a)
    {
        return await a;
    }

    static async Task<int> Faulted()
    {
        var src = new TaskCompletionSource<int>();
        src.SetException(new Exception("boom"));
        return await src.Task;
    }

    static async Task<int> Caught()
    {
        var src = new TaskCompletionSource<int>();
        src.SetException(new Exception("boom"));
        try
        {
            return await src.Task;
        }
        catch
        {
            return -1;
        }
    }

    static async Task<int> Raises()
    {
        throw new Exception("plain");
    }
#pragma warning restore CS1998

    static async Task<int> Branch(int n)
    {
        if (n > 0)
        {
            await Done;
            return 1;
        }
        else
        {
            await Done;
            return 2;
        }
    }

    static async Task<int> WhileSum()
    {
        int i = 1;
        int s = 0;
        while (i <= 3)
        {
            int v = await Done;
            s = s + i;
            if (v != 1)
                s = -100;
            i = i + 1;
        }
        return s;
    }

    static async Task<int> ForSum()
    {
        int s = 0;
        for (int i = 1; i <= 3; i++)
        {
            await Done;
            s = s + i;
        }
        return s;
    }

    static async Task<int> BreakAt()
    {
        int result = 0;
        for (int i = 1; i <= 5; i++)
        {
            await Done;
            if (i == 3)
                break;
            result = result + i;
        }
        return result;
    }

    static async Task<int> Early()
    {
        await Done;
        return 5;
    }

    static async Task<int> WithFinally()
    {
        try
        {
            await Task.Delay(200);
        }
        finally
        {
            FinallyFlag = 1;
        }
        return FinallyFlag;
    }

    static async Task<string> Sticky()
    {
        string s = "ab";
        await Task.Delay(30);
        return s + "c";
    }

    static async Task<int> DownToSum()
    {
        int s = 0;
        for (int i = 3; i >= 1; i--)
        {
            await Done;
            s = s + i;
        }
        return s;
    }

    static async Task<int> ContinueSum()
    {
        int s = 0;
        for (int i = 1; i <= 5; i++)
        {
            if (i == 3)
                continue;
            await Done;
            s = s + i;
        }
        return s;
    }

    static async Task<int> RepeatThree()
    {
        int i = 0;
        do
        {
            i = i + 1;
            await Done;
            continue;
        }
        while (i != 3);
        return i;
    }

    static async Task WaitOnly()
    {
        await DoneTask;
    }

    static async Task<int> OneOf(int n)
    {
        await Task.Delay(30);
        return n;
    }

    static async Task<int> Chain(Task<int> a)
    {
        int s = 0;
        for (int i = 1; i <= 100; i++)
        {
            int v = await a;
            s = s + v;
        }
        return s;
    }

    static bool ReadRaises(Task<int> f)
    {
        try
        {
            if (f.Result == 0)
                return false;
            return false;
        }
        catch
        {
            return true;
        }
    }

    static async Task<int> Main()
    {
        Console.WriteLine("# sm-compare csharp");

        long t0 = Now();
        int bad = 0;
        for (int i = 1; i <= 2000; i++)
            if (await SyncOne() != 1)
                bad++;
        Line("01", "sync_x2000", Elapsed(t0), bad == 0);

        t0 = Now();
        Task<int> f = Pipeline();
        long callMs = Elapsed(t0);
        Line("02", "call_returns_early", callMs,
            (callMs < 40) && !f.IsCompleted && (await f == 42));

        t0 = Now();
        f = Take(Task.FromResult(7));
        callMs = Elapsed(t0);
        Line("03", "await_completed", callMs, (callMs < 40) && (await f == 7));

        t0 = Now();
        bool raised = ReadRaises(Faulted());
        Line("04", "faulted_raises", Elapsed(t0), raised);

        t0 = Now();
        int caught = await Caught();
        Line("05", "except_sets_minus1", Elapsed(t0), caught == -1);

        t0 = Now();
        raised = ReadRaises(Raises());
        Line("06", "raise_faults", Elapsed(t0), raised);

        t0 = Now();
        int branch = await Branch(1);
        Line("07", "if_then", Elapsed(t0), branch == 1);

        t0 = Now();
        branch = await Branch(-1);
        Line("08", "if_else", Elapsed(t0), branch == 2);

        t0 = Now();
        int sum = await WhileSum();
        Line("09", "while_sum", Elapsed(t0), sum == 6);

        t0 = Now();
        sum = await ForSum();
        Line("10", "for_sum", Elapsed(t0), sum == 6);

        t0 = Now();
        sum = await BreakAt();
        Line("11", "break_is_3", Elapsed(t0), sum == 3);

        t0 = Now();
        sum = await Early();
        Line("12", "exit_keeps_5", Elapsed(t0), sum == 5);

        FinallyFlag = 0;
        t0 = Now();
        f = WithFinally();
        callMs = Elapsed(t0);
        int flagAtReturn = FinallyFlag;
        Line("13", "finally_after_resume", callMs,
            (callMs < 40) && (flagAtReturn == 0) && (await f == 1) && (FinallyFlag == 1));

        t0 = Now();
        Task<string> fs = Sticky();
        string text = await fs;
        Line("14", "string_abc", Elapsed(t0), text == "abc");

        t0 = Now();
        sum = await DownToSum();
        Line("15", "downto_sum", Elapsed(t0), sum == 6);

        t0 = Now();
        sum = await ContinueSum();
        Line("16", "continue_sum", Elapsed(t0), sum == 12);

        t0 = Now();
        sum = await RepeatThree();
        Line("17", "repeat_is_3", Elapsed(t0), sum == 3);

        t0 = Now();
        Task tk = WaitOnly();
        await tk;
        Line("18", "itask_completes", Elapsed(t0), tk.IsCompleted);

        var futs = new Task<int>[100];
        t0 = Now();
        for (int i = 0; i < 100; i++)
            futs[i] = OneOf(i + 1);
        await Task.WhenAll(futs);
        int s = 0;
        for (int i = 0; i < 100; i++)
            s = s + futs[i].Result;
        long took = Elapsed(t0);
        Line("19", "concurrent_100x30ms", took, (s == 5050) && (took >= 20));

        t0 = Now();
        sum = await Chain(Done);
        Line("20", "chain_100", Elapsed(t0), sum == 100);

        Console.WriteLine("PASSED " + Passed + "/20");
        return Failed == 0 ? 0 : 1;
    }
}
