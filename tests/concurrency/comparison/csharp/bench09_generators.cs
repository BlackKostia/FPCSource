using System;
using System.Collections.Generic;
using System.Diagnostics;

class Program
{
    const int TotalCount = 100000;

    static IEnumerable<long> GenerateSequence()
    {
        for (int i = 1; i <= TotalCount; i++)
        {
            yield return i;
        }
    }

    static void Main()
    {
        Console.WriteLine("=== Benchmark 9 (C#): IEnumerable with yield return ===");
        var sw = Stopwatch.StartNew();

        long sum = 0;
        foreach (long val in GenerateSequence())
        {
            sum += val;
        }

        sw.Stop();
        Console.WriteLine($"Generated and consumed {TotalCount} values in: {sw.ElapsedMilliseconds} ms");
        Console.WriteLine($"Computed sum: {sum}");

        if (sum == 5000050000L)
            Console.WriteLine("BENCHMARK 9 PASSED");
        else
            Environment.Exit(1);
    }
}

