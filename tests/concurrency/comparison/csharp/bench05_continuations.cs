using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

class Program
{
    static void Main()
    {
        Console.WriteLine("=== Benchmark 5 (C#): Task.ContinueWith Pipeline ===");
        var sw = Stopwatch.StartNew();

        Task<int> f0 = Task.Run(() =>
        {
            Thread.Sleep(30);
            return 21;
        });

        Task<string> f1 = f0.ContinueWith(prev =>
        {
            Thread.Sleep(20);
            return $"Result: {prev.Result * 2}";
        });

        Task<int> f2 = f1.ContinueWith(prev =>
        {
            string s = prev.Result;
            int num = int.Parse(s.Substring(8));
            return num + 8;
        });

        int finalResult = f2.Result;
        sw.Stop();

        Console.WriteLine($"Chained pipeline computed: {finalResult} in {sw.ElapsedMilliseconds} ms");
        if (finalResult == 50 && sw.ElapsedMilliseconds >= 45)
            Console.WriteLine("BENCHMARK 5 PASSED");
        else
            Environment.Exit(1);
    }
}

