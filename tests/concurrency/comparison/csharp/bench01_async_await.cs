using System;
using System.Diagnostics;
using System.Threading.Tasks;

class Program
{
    static async Task<int> DelayAsync(int ms, int val)
    {
        await Task.Delay(ms);
        return val;
    }

    static async Task<int> ComputeAsync(int x)
    {
        int a = await DelayAsync(40, x);
        int b = await DelayAsync(40, a * 2);
        return b + 10;
    }

    static async Task Main()
    {
        Console.WriteLine("=== Benchmark 1 (C#): Async / Await Task ===");
        var sw = Stopwatch.StartNew();
        
        Task<int> task = ComputeAsync(25);
        long tookCall = sw.ElapsedMilliseconds;

        Console.WriteLine($"Call to async method took: {tookCall} ms (Non-blocking: {tookCall < 20})");

        int res = await task;
        long tookTotal = sw.ElapsedMilliseconds;

        Console.WriteLine($"Computed result: {res} (Expected: 60)");
        Console.WriteLine($"Total execution time: {tookTotal} ms");
        if (res == 60 && tookCall < 20 && tookTotal >= 70)
            Console.WriteLine("BENCHMARK 1 PASSED");
        else
            Environment.Exit(1);
    }
}

