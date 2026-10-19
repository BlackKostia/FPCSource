using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;

public struct Transaction
{
    public long TxId;
    public int AccountFrom;
    public int AccountTo;
    public long Amount;
    public ulong Timestamp;
}

public struct Confirmation
{
    public long TxId;
    public int Status;
    public long Fee;
    public ulong Signature;
}

public class Program
{
    private const int TotalTransactions = 1000000;
    private const int NumProducers = 6;
    private const int NumWorkers = 6;
    private const int BufferCapacity = 50000;

    private static readonly Channel<Transaction> InboundChannel = Channel.CreateBounded<Transaction>(BufferCapacity);
    private static readonly Channel<Confirmation> OutboundChannel = Channel.CreateBounded<Confirmation>(BufferCapacity);

    private static long _totalConfirmed = 0;
    private static long _totalFees = 0;
    private static ulong _auditChecksum = 0;

    private static ulong ComputeHash(long txId, long amount)
    {
        ulong h = ((ulong)txId) ^ (((ulong)amount) << 16);
        for (int s = 1; s <= 20; s++)
        {
            h = h * 6364136223846793005UL + 1442695040888963407UL;
        }
        return h;
    }

    private static async Task RunProducerAsync(int idx)
    {
        int chunk = TotalTransactions / NumProducers;
        int startI = idx * chunk + 1;
        int endI = (idx == NumProducers - 1) ? TotalTransactions + 1 : (idx + 1) * chunk + 1;

        var writer = InboundChannel.Writer;
        for (int i = startI; i < endI; i++)
        {
            var tx = new Transaction
            {
                TxId = i,
                AccountFrom = (i % 10000) + 1,
                AccountTo = ((i + 42) % 10000) + 1,
                Amount = (i % 5000) + 10,
                Timestamp = (ulong)Stopwatch.GetTimestamp()
            };
            await writer.WriteAsync(tx);
        }
    }

    private static async Task RunWorkerAsync()
    {
        var reader = InboundChannel.Reader;
        var writer = OutboundChannel.Writer;

        while (await reader.WaitToReadAsync())
        {
            while (reader.TryRead(out var tx))
            {
                var conf = new Confirmation
                {
                    TxId = tx.TxId,
                    Status = 1,
                    Fee = (tx.Amount * 15) / 10000,
                    Signature = ComputeHash(tx.TxId, tx.Amount)
                };
                await writer.WriteAsync(conf);
            }
        }
    }

    private static async Task RunAuditorAsync()
    {
        var reader = OutboundChannel.Reader;
        while (await reader.WaitToReadAsync())
        {
            while (reader.TryRead(out var conf))
            {
                _totalConfirmed++;
                _totalFees += conf.Fee;
                _auditChecksum ^= conf.Signature;
            }
        }
    }

    public static void Main()
    {
        Console.WriteLine("=== C# (.NET 8): Channel Pipeline Data Exchange (1,000,000 txs) ===");
        Console.WriteLine($"Producers: {NumProducers}, Workers: {NumWorkers}, Auditor: 1");

        var sw = Stopwatch.StartNew();

        // 1. Auditor
        var auditorTask = Task.Run(RunAuditorAsync);

        // 2. Workers
        var workerTasks = new Task[NumWorkers];
        for (int i = 0; i < NumWorkers; i++)
            workerTasks[i] = Task.Run(RunWorkerAsync);

        // 3. Producers
        var producerTasks = new Task[NumProducers];
        for (int i = 0; i < NumProducers; i++)
        {
            int pIdx = i;
            producerTasks[i] = Task.Run(() => RunProducerAsync(pIdx));
        }

        // Wait for producers to finish
        Task.WaitAll(producerTasks);
        InboundChannel.Writer.Complete();

        // Wait for workers to finish
        Task.WaitAll(workerTasks);
        OutboundChannel.Writer.Complete();

        // Wait for auditor
        auditorTask.GetAwaiter().GetResult();
        sw.Stop();

        long tookMs = sw.ElapsedMilliseconds;
        Console.WriteLine($"Successfully processed & exchanged {_totalConfirmed} transactions!");
        Console.WriteLine($"Execution time: {tookMs} ms");
        Console.WriteLine($"Throughput: {TotalTransactions / (tookMs / 1000.0):F1} tx/sec");
        Console.WriteLine($"Total data transfers: {_totalConfirmed * 2} items across threads");
        Console.WriteLine($"Total fees: ${_totalFees / 100}.{_totalFees % 100:D2}");
        Console.WriteLine($"Audit checksum: {_auditChecksum}");
    }
}

