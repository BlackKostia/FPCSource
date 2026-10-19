using System;
using System.Diagnostics;

class Program
{
    static (int count, long sum) ComputeStats(int limit)
    {
        long s = 0;
        for (int i = 1; i <= limit; i++) s += i;
        return (limit, s);
    }

    static void Main()
    {
        Console.WriteLine("=== Benchmark 6 (C#): ValueTuples & Deconstruction ===");
        var sw = Stopwatch.StartNew();

        var (c, s) = ComputeStats(1000);

        int x = 10;
        int y = 20;
        for (int i = 0; i < 10000000; i++)
        {
            (x, y) = (y, x);
        }

        sw.Stop();
        Console.WriteLine($"Tuple deconstruction: Count = {c}, Sum = {s}");
        Console.WriteLine($"Swapped X = {x}, Y = {y}");
        Console.WriteLine($"10,000,000 tuple swap operations took: {sw.ElapsedMilliseconds} ms");

        if (c == 1000 && s == 500500 && x == 10 && y == 20)
            Console.WriteLine("BENCHMARK 6 PASSED");
        else
            Environment.Exit(1);
    }
}

