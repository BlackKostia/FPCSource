using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

class Program
{
    const int ReadOpsPerThread = 100000;
    const int WriteOpsPerThread = 10000;

    static void Main()
    {
        Console.WriteLine("=== Benchmark 8 (C#): ReaderWriterLockSlim High Contention ===");
        var rwLock = new ReaderWriterLockSlim();
        long sharedCounter = 0;
        var sw = Stopwatch.StartNew();

        Task[] tasks = new Task[6];

        // 4 Readers
        for (int i = 0; i < 4; i++)
        {
            tasks[i] = Task.Run(() =>
            {
                for (int j = 0; j < ReadOpsPerThread; j++)
                {
                    rwLock.EnterReadLock();
                    try
                    {
                        long v = sharedCounter;
                    }
                    finally
                    {
                        rwLock.ExitReadLock();
                    }
                }
            });
        }

        // 2 Writers
        for (int i = 4; i < 6; i++)
        {
            tasks[i] = Task.Run(() =>
            {
                for (int j = 0; j < WriteOpsPerThread; j++)
                {
                    rwLock.EnterWriteLock();
                    try
                    {
                        sharedCounter++;
                    }
                    finally
                    {
                        rwLock.ExitWriteLock();
                    }
                }
            });
        }

        Task.WaitAll(tasks);
        sw.Stop();

        Console.WriteLine($"Completed 400,000 reads + 20,000 writes in: {sw.ElapsedMilliseconds} ms");
        Console.WriteLine($"Final SharedCounter: {sharedCounter} (Expected: 20000)");

        rwLock.Dispose();
        if (sharedCounter == 20000)
            Console.WriteLine("BENCHMARK 8 PASSED");
        else
            Environment.Exit(1);
    }
}

