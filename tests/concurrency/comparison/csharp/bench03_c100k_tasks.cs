using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

class Program
{
    const int TotalCoroutines = 20000;

    static async Task Main()
    {
        Console.WriteLine("=== Benchmark 3 (C#): 20,000 Concurrent Async Tasks ===");
        var sw = Stopwatch.StartNew();

        int completedCount = 0;
        long totalSum = 0;

        Task[] tasks = new Task[TotalCoroutines];
        for (int i = 0; i < TotalCoroutines; i++)
        {
            tasks[i] = Task.Run(async () =>
            {
                await Task.Delay(20);
                Interlocked.Increment(ref completedCount);
                Interlocked.Add(ref totalSum, 1);
            });
        }

        await Task.WhenAll(tasks);
        sw.Stop();

        Console.WriteLine($"All {completedCount} tasks completed in: {sw.ElapsedMilliseconds} ms");
        Console.WriteLine($"Total accumulated sum: {totalSum}");

        if (completedCount == TotalCoroutines && totalSum == TotalCoroutines)
            Console.WriteLine("BENCHMARK 3 PASSED");
        else
            Environment.Exit(1);
    }
}

