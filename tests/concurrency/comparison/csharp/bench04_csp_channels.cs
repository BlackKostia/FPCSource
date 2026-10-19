using System;
using System.Diagnostics;
using System.Threading.Channels;
using System.Threading.Tasks;

class Program
{
    const int ItemCount = 100000;

    static async Task Main()
    {
        Console.WriteLine("=== Benchmark 4 (C#): System.Threading.Channels.Channel ===");
        var channel = Channel.CreateBounded<int>(new BoundedChannelOptions(1024)
        {
            FullMode = BoundedChannelFullMode.Wait
        });

        long consumedSum = 0;
        var sw = Stopwatch.StartNew();

        var producer = Task.Run(async () =>
        {
            for (int i = 1; i <= ItemCount; i++)
            {
                await channel.Writer.WriteAsync(i);
            }
            channel.Writer.Complete();
        });

        var consumer = Task.Run(async () =>
        {
            await foreach (int msg in channel.Reader.ReadAllAsync())
            {
                consumedSum += msg;
            }
        });

        await Task.WhenAll(producer, consumer);
        sw.Stop();

        Console.WriteLine($"Transferred {ItemCount} messages in: {sw.ElapsedMilliseconds} ms");
        Console.WriteLine($"Calculated sum: {consumedSum}");

        if (consumedSum == 5000050000L)
            Console.WriteLine("BENCHMARK 4 PASSED");
        else
            Environment.Exit(1);
    }
}

