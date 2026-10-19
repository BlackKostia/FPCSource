using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

class Program
{
    static void Main()
    {
        Console.WriteLine("=== Benchmark 7 (C#): CancellationTokenSource ===");
        var cts = new CancellationTokenSource();
        CancellationToken token = cts.Token;

        int loopsDone = 0;
        var sw = Stopwatch.StartNew();

        Task task1 = Task.Run(() =>
        {
            while (!token.IsCancellationRequested)
            {
                Thread.Sleep(5);
                loopsDone++;
            }
        });

        Thread.Sleep(50);
        cts.Cancel();

        task1.Wait();
        sw.Stop();

        Console.WriteLine($"Task terminated gracefully after {loopsDone} iterations in: {sw.ElapsedMilliseconds} ms");
        cts.Dispose();

        if (loopsDone >= 5 && sw.ElapsedMilliseconds < 150)
            Console.WriteLine("BENCHMARK 7 PASSED");
        else
            Environment.Exit(1);
    }
}

