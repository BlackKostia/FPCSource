using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;

public struct RawMessage
{
    public long MsgId;
    public int AccountId;
    public long Amount;
    public ulong Payload;
}

public struct EnrichedMessage
{
    public long MsgId;
    public int ShardId;
    public long Fee;
    public ulong Signature;
}

public class Program
{
    private const int TotalMessages = 2000000;
    private const int NumProducers = 4;
    private const int NumShards = 4;
    private const int IngestCapacity = 50000;
    private const int ShardCapacity = 25000;
    private const int OutboundCapacity = 50000;

    private static readonly Channel<RawMessage> IngestChannel = Channel.CreateBounded<RawMessage>(IngestCapacity);
    private static readonly Channel<RawMessage>[] ShardChannels = new Channel<RawMessage>[NumShards];
    private static readonly Channel<EnrichedMessage> OutboundChannel = Channel.CreateBounded<EnrichedMessage>(OutboundCapacity);

    private static long _totalAggregated = 0;
    private static long _totalFees = 0;
    private static ulong _aggregatorChecksum = 0;

    private static ulong ComputeRiskSignature(long msgId, long amount, int shardId)
    {
        ulong h = ((ulong)msgId) ^ (((ulong)amount) << 16) ^ ((ulong)(shardId * 7919));
        for (int s = 1; s <= 20; s++)
        {
            h = h * 6364136223846793005UL + 1442695040888963407UL;
        }
        return h;
    }

    private static async Task RunProducerAsync(int prodIdx)
    {
        int chunk = TotalMessages / NumProducers;
        int startI = prodIdx * chunk + 1;
        int endI = (prodIdx == NumProducers - 1) ? TotalMessages + 1 : (prodIdx + 1) * chunk + 1;

        var writer = IngestChannel.Writer;
        for (int i = startI; i < endI; i++)
        {
            var msg = new RawMessage
            {
                MsgId = i,
                AccountId = (i % 100000) + 1,
                Amount = (i % 5000) + 10,
                Payload = (ulong)(i * 1337)
            };
            await writer.WriteAsync(msg);
        }
    }

    private static async Task RunRouterAsync()
    {
        var reader = IngestChannel.Reader;
        while (await reader.WaitToReadAsync())
        {
            while (reader.TryRead(out var msg))
            {
                int shardIdx = msg.AccountId % NumShards;
                await ShardChannels[shardIdx].Writer.WriteAsync(msg);
            }
        }

        for (int s = 0; s < NumShards; s++)
            ShardChannels[s].Writer.Complete();
    }

    private static async Task RunShardWorkerAsync(int shardIdx)
    {
        var reader = ShardChannels[shardIdx].Reader;
        var writer = OutboundChannel.Writer;

        while (await reader.WaitToReadAsync())
        {
            while (reader.TryRead(out var msg))
            {
                var enriched = new EnrichedMessage
                {
                    MsgId = msg.MsgId,
                    ShardId = shardIdx,
                    Fee = (msg.Amount * 15) / 10000,
                    Signature = ComputeRiskSignature(msg.MsgId, msg.Amount, shardIdx)
                };
                await writer.WriteAsync(enriched);
            }
        }
    }

    private static async Task RunAggregatorAsync()
    {
        var reader = OutboundChannel.Reader;
        while (await reader.WaitToReadAsync())
        {
            while (reader.TryRead(out var enriched))
            {
                _totalAggregated++;
                _totalFees += enriched.Fee;
                _aggregatorChecksum ^= enriched.Signature;
            }
        }
    }

    public static void Main()
    {
        Console.WriteLine("=== C# (.NET 8): DAG Actor Pipeline (2,000,000 Messages) ===");
        Console.WriteLine("Topology: 4 Producers -> IngestChannel -> Router -> 4 ShardChannels -> 4 Workers -> OutboundChannel -> Aggregator");

        for (int i = 0; i < NumShards; i++)
            ShardChannels[i] = Channel.CreateBounded<RawMessage>(ShardCapacity);

        var sw = Stopwatch.StartNew();

        // 1. Aggregator
        var aggregatorTask = Task.Run(RunAggregatorAsync);

        // 2. Shard Workers
        var shardTasks = new Task[NumShards];
        for (int i = 0; i < NumShards; i++)
        {
            int sIdx = i;
            shardTasks[i] = Task.Run(() => RunShardWorkerAsync(sIdx));
        }

        // 3. Router
        var routerTask = Task.Run(RunRouterAsync);

        // 4. Producers
        var producerTasks = new Task[NumProducers];
        for (int i = 0; i < NumProducers; i++)
        {
            int pIdx = i;
            producerTasks[i] = Task.Run(() => RunProducerAsync(pIdx));
        }

        // Wait for Producers -> complete Ingest
        Task.WaitAll(producerTasks);
        IngestChannel.Writer.Complete();

        // Wait for Router
        routerTask.GetAwaiter().GetResult();

        // Wait for Shard Workers -> complete Outbound
        Task.WaitAll(shardTasks);
        OutboundChannel.Writer.Complete();

        // Wait for Aggregator
        aggregatorTask.GetAwaiter().GetResult();
        sw.Stop();

        long tookMs = sw.ElapsedMilliseconds;
        Console.WriteLine($"Successfully processed DAG through all stages: {_totalAggregated} messages");
        Console.WriteLine($"Total execution time: {tookMs} ms");
        Console.WriteLine($"Throughput: {TotalMessages / (tookMs / 1000.0):F1} msgs/sec");
        Console.WriteLine($"Total fees: ${_totalFees / 100}.{_totalFees % 100:D2}");
        Console.WriteLine($"Aggregator checksum: {_aggregatorChecksum}");
    }
}

