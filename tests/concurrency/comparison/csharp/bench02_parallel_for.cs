using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

class Program
{
    const int N = 1000000;

    static void Main()
    {
        Console.WriteLine("=== Benchmark 2 (C#): Parallel.For CPU Workload ===");
        int[] data = new int[N];
        for (int i = 0; i < N; i++) data[i] = i;

        long totalMatches = 0;
        var sw = Stopwatch.StartNew();

        Parallel.For(0, N, idx =>
        {
            int v = data[idx];
            if (((v ^ 1234567) % 1000) == 0)
            {
                Interlocked.Increment(ref totalMatches);
            }
        });

        sw.Stop();
        Console.WriteLine($"Processed {N} items in parallel in: {sw.ElapsedMilliseconds} ms");
        Console.WriteLine($"Total matches found: {totalMatches}");
        if (totalMatches == 1001)
            Console.WriteLine("BENCHMARK 2 PASSED");
        else
            Environment.Exit(1);
    }
}
