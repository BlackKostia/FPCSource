using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;

public struct TradeEvent
{
    public int KeyId;
    public long Price;
    public ulong Checksum;
}

public class Program
{
    private const int TotalOps = 500000;
    private const int KeysCount = 1000;
    private const int NumWorkers = 12;

    private static readonly long[] Cache = new long[KeysCount];
    private static readonly ReaderWriterLockSlim CacheLock = new ReaderWriterLockSlim();
    private static readonly Channel<TradeEvent> TradeChannel = Channel.CreateBounded<TradeEvent>(50000);

    private static long _consumedTrades = 0;
    private static ulong _consumerXor = 0;
    private static long _totalReadSum = 0;

    private static ulong ComputeRiskHash(long val, int iter)
    {
        ulong h = ((ulong)val) ^ ((ulong)iter);
        for (int s = 1; s <= 30; s++)
        {
            h = h * 6364136223846793005UL + 1442695040888963407UL;
        }
        return h;
    }

    private static async Task RunConsumerAsync()
    {
        var reader = TradeChannel.Reader;
        while (await reader.WaitToReadAsync())
        {
            while (reader.TryRead(out var ev))
            {
                _consumedTrades++;
                _consumerXor ^= ev.Checksum;
            }
        }
    }

    public static void Main()
    {
        Console.WriteLine("=== C# (.NET 8): ReaderWriterLockSlim + Channel<T> + Parallel.For ===");

        for (int i = 0; i < KeysCount; i++)
            Cache[i] = (i + 1) * 100;

        var consumerTask = Task.Run(RunConsumerAsync);

        var sw = Stopwatch.StartNew();

        Parallel.For(0, NumWorkers, new ParallelOptions { MaxDegreeOfParallelism = NumWorkers }, workerIdx =>
        {
            int chunkSize = TotalOps / NumWorkers;
            int startI = workerIdx * chunkSize;
            int endI = (workerIdx == NumWorkers - 1) ? TotalOps : (workerIdx + 1) * chunkSize;

            long localReadSum = 0;
            long val = 0;

            for (int i = startI; i < endI; i++)
            {
                int keyId = i % KeysCount;
                if (i % 10 != 0)
                {
                    // 90% Reads
                    CacheLock.EnterReadLock();
                    try
                    {
                        val = Cache[keyId];
                    }
                    finally
                    {
                        CacheLock.ExitReadLock();
                    }
                    localReadSum += val ^ (i & 15);
                }
                else
                {
                    // 10% Writes + Channel event
                    CacheLock.EnterWriteLock();
                    try
                    {
                        Cache[keyId] = val + (i % 50);
                        val = Cache[keyId];
                    }
                    finally
                    {
                        CacheLock.ExitWriteLock();
                    }

                    var ev = new TradeEvent
                    {
                        KeyId = keyId,
                        Price = val,
                        Checksum = ComputeRiskHash(val, i)
                    };
                    TradeChannel.Writer.TryWrite(ev);
                }
            }

            Interlocked.Add(ref _totalReadSum, localReadSum);
        });

        TradeChannel.Writer.Complete();
        consumerTask.GetAwaiter().GetResult();
        sw.Stop();

        long tookMs = sw.ElapsedMilliseconds;
        Console.WriteLine($"Processed {TotalOps} ops in: {tookMs} ms");
        Console.WriteLine($"Throughput: {TotalOps / (tookMs / 1000.0):F1} ops/sec");
        Console.WriteLine($"Consumed trade events: {_consumedTrades}, Consumer XOR: {_consumerXor}");
        Console.WriteLine($"Total read sum: {_totalReadSum}");
    }
}
