using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;

class Program
{
    static async Task<int> Level3Async()
    {
        await Task.Delay(20);
        throw new IOException("Deep I/O failure at Level 3");
    }

    static async Task<int> Level2Async()
    {
        int v = await Level3Async();
        return v + 1;
    }

    static async Task<int> Level1Async()
    {
        int v = await Level2Async();
        return v + 1;
    }

    static async Task Main()
    {
        Console.WriteLine("=== Benchmark 10 (C#): Deep Async Exception Propagation ===");
        var sw = Stopwatch.StartNew();

        bool caught = false;
        string errMsg = "";

        try
        {
            await Level1Async();
        }
        catch (Exception ex)
        {
            caught = true;
            errMsg = ex.Message;
        }

        sw.Stop();
        Console.WriteLine($"Exception propagated across 3 async levels in: {sw.ElapsedMilliseconds} ms");
        Console.WriteLine($"Caught message: \"{errMsg}\"");

        if (caught && errMsg.Contains("Deep I/O failure at Level 3"))
            Console.WriteLine("BENCHMARK 10 PASSED");
        else
            Environment.Exit(1);
    }
}

