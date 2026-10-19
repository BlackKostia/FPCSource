// =====================================================================
// High-Performance Multithreaded In-Memory KV & Compute HTTP Server (C#)
// Standard .NET 8 / C# 12 Implementation
// =====================================================================

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Channels;
using System.Threading.Tasks;

class Program
{
    const int Port = 9004;
    const int Backlog = 8192;

    record LogEntry(long Timestamp, string Method, string Path, int StatusCode);

    static readonly Dictionary<string, string> Cache = new();
    static readonly ReaderWriterLockSlim CacheLock = new();
    static readonly Channel<LogEntry> LogChannel = Channel.CreateBounded<LogEntry>(new BoundedChannelOptions(100000)
    {
        FullMode = BoundedChannelFullMode.DropOldest
    });

    static long _totalRequests = 0;
    static long _totalReads = 0;
    static long _totalWrites = 0;
    static long _totalComputes = 0;
    static readonly Stopwatch Uptime = Stopwatch.StartNew();

    static async Task Main(string[] args)
    {
        // Configure ThreadPool for high connection concurrency
        ThreadPool.SetMinThreads(64, 64);
        ThreadPool.SetMaxThreads(256, 256);

        // Start background telemetry consumer
        _ = Task.Run(async () =>
        {
            await foreach (var entry in LogChannel.Reader.ReadAllAsync())
            {
                // Background telemetry aggregation
            }
        });

        using var server = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
        server.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        server.Bind(new IPEndPoint(IPAddress.Any, Port));
        server.Listen(Backlog);

        Console.WriteLine($"C# (.NET 8 ThreadPool, RWLockSlim, Channels) server listening on port {Port}...");

        while (true)
        {
            var client = await server.AcceptAsync();
            _ = Task.Run(() => HandleClient(client));
        }
    }

    static long ComputeWork(int n)
    {
        long s = 0;
        for (int i = 0; i < n; i++)
        {
            s ^= ((long)i * 37) & 0xFFFFFFFF;
        }
        return s;
    }

    static string ExtractParam(string query, string name)
    {
        string prefix = name + "=";
        int p = query.IndexOf(prefix, StringComparison.Ordinal);
        if (p >= 0)
        {
            p += prefix.Length;
            int endP = query.IndexOf('&', p);
            return endP >= 0 ? query.Substring(p, endP - p) : query.Substring(p);
        }
        return "";
    }

    static void HandleClient(Socket client)
    {
        try
        {
            byte[] buffer = new byte[4096];
            int bytesRead = client.Receive(buffer);
            if (bytesRead <= 0) return;

            string reqStr = Encoding.UTF8.GetString(buffer, 0, bytesRead);
            int lineEnd = reqStr.IndexOf("\r\n", StringComparison.Ordinal);
            string line = lineEnd > 0 ? reqStr.Substring(0, lineEnd) : reqStr;
            string[] parts = line.Split(' ');
            if (parts.Length < 2) return;

            string method = parts[0];
            string fullPath = parts[1];

            int qPos = fullPath.IndexOf('?');
            string path = qPos > 0 ? fullPath.Substring(0, qPos) : fullPath;
            string queryStr = qPos > 0 ? fullPath.Substring(qPos + 1) : "";

            int statusCode = 200;
            string statusText = "OK";
            string responseBody;

            if (path == "/stats")
            {
                double uptimeSec = Uptime.Elapsed.TotalSeconds;
                int cacheSize;
                CacheLock.EnterReadLock();
                try { cacheSize = Cache.Count; }
                finally { CacheLock.ExitReadLock(); }

                responseBody = JsonSerializer.Serialize(new
                {
                    server = "C# (.NET 8 ThreadPool, ReaderWriterLockSlim, Channel<T>)",
                    uptime_s = Math.Round(uptimeSec, 2),
                    total_requests = Interlocked.Read(ref _totalRequests),
                    reads = Interlocked.Read(ref _totalReads),
                    writes = Interlocked.Read(ref _totalWrites),
                    computes = Interlocked.Read(ref _totalComputes),
                    cache_size = cacheSize
                });
            }
            else if (path == "/get")
            {
                string key = ExtractParam(queryStr, "key");
                string val = null;
                CacheLock.EnterReadLock();
                try
                {
                    Cache.TryGetValue(key, out val);
                }
                finally
                {
                    CacheLock.ExitReadLock();
                }

                Interlocked.Increment(ref _totalRequests);
                Interlocked.Increment(ref _totalReads);

                responseBody = JsonSerializer.Serialize(new
                {
                    key = key,
                    val = val,
                    found = val != null
                });
            }
            else if (path == "/set")
            {
                string key = ExtractParam(queryStr, "key");
                string val = ExtractParam(queryStr, "val");
                CacheLock.EnterWriteLock();
                try
                {
                    Cache[key] = val;
                }
                finally
                {
                    CacheLock.ExitWriteLock();
                }

                Interlocked.Increment(ref _totalRequests);
                Interlocked.Increment(ref _totalWrites);

                responseBody = JsonSerializer.Serialize(new
                {
                    key = key,
                    val = val,
                    status = "stored"
                });
            }
            else if (path == "/work")
            {
                int.TryParse(ExtractParam(queryStr, "n"), out int n);
                if (n <= 0) n = 1000;
                long workRes = ComputeWork(n);

                Interlocked.Increment(ref _totalRequests);
                Interlocked.Increment(ref _totalComputes);

                responseBody = JsonSerializer.Serialize(new
                {
                    work_n = n,
                    result = workRes
                });
            }
            else
            {
                statusCode = 404;
                statusText = "Not Found";
                responseBody = "{\"error\":\"Not Found\"}";
            }

            // Asynchronously dispatch to Channel
            LogChannel.Writer.TryWrite(new LogEntry(Stopwatch.GetTimestamp(), method, path, statusCode));

            byte[] bodyBytes = Encoding.UTF8.GetBytes(responseBody);
            string headers = $"HTTP/1.1 {statusCode} {statusText}\r\n" +
                             $"Content-Type: application/json\r\n" +
                             $"Content-Length: {bodyBytes.Length}\r\n" +
                             $"Connection: close\r\n\r\n";
            byte[] headerBytes = Encoding.UTF8.GetBytes(headers);

            client.Send(headerBytes);
            client.Send(bodyBytes);
        }
        finally
        {
            client.Dispose();
        }
    }
}

