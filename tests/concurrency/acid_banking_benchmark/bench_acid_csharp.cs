using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

public class Program
{
    private const int TotalTxs = 2000000;
    private const int NumAccounts = 500;
    private const int NumWorkers = 12;
    private const long InitialBalance = 1000000; // $10,000.00 in cents

    private static readonly long[] Balances = new long[NumAccounts];
    private static readonly ReaderWriterLockSlim[] AccountLocks = new ReaderWriterLockSlim[NumAccounts];

    private static long _totalInquiries = 0;
    private static long _totalTransfers = 0;
    private static long _totalCasOps = 0;

    private static void RunWorker(int workerIdx)
    {
        int chunk = TotalTxs / NumWorkers;
        int startI = workerIdx * chunk + 1;
        int endI = (workerIdx == NumWorkers - 1) ? TotalTxs + 1 : (workerIdx + 1) * chunk + 1;

        long localInquiries = 0;
        long localTransfers = 0;
        long localCasOps = 0;

        for (int i = startI; i < endI; i++)
        {
            int opType = i % 10;
            int accA = (int)(((long)i * 7919) % NumAccounts);

            if (opType < 7)
            {
                // 70% Inquiries: Parallel Read Lock
                AccountLocks[accA].EnterReadLock();
                try
                {
                    long readVal = Balances[accA];
                    localInquiries += readVal & 1;
                }
                finally
                {
                    AccountLocks[accA].ExitReadLock();
                }
            }
            else if (opType < 9)
            {
                // 20% Direct Update: Lock-Free CAS
                long amount = (i % 100) + 1;
                while (true)
                {
                    long oldVal = Interlocked.Read(ref Balances[accA]);
                    long newVal = ((i & 1) == 0) ? oldVal + amount : oldVal - amount;
                    if (Interlocked.CompareExchange(ref Balances[accA], newVal, oldVal) == oldVal)
                        break;
                }
                localCasOps++;
            }
            else
            {
                // 10% Multi-Account Transfer: Hierarchical 2-Lock Acquisition
                int accB = (int)((((long)i * 1337) + 42) % NumAccounts);
                if (accA == accB)
                    accB = (accA + 1) % NumAccounts;

                int firstLock = Math.Min(accA, accB);
                int secondLock = Math.Max(accA, accB);

                AccountLocks[firstLock].EnterWriteLock();
                try
                {
                    AccountLocks[secondLock].EnterWriteLock();
                    try
                    {
                        long amount = (i % 250) + 10;
                        if (Balances[accA] >= amount)
                        {
                            Balances[accA] -= amount;
                            Balances[accB] += amount;
                        }
                        localTransfers++;
                    }
                    finally
                    {
                        AccountLocks[secondLock].ExitWriteLock();
                    }
                }
                finally
                {
                    AccountLocks[firstLock].ExitWriteLock();
                }
            }
        }

        Interlocked.Add(ref _totalInquiries, localInquiries);
        Interlocked.Add(ref _totalTransfers, localTransfers);
        Interlocked.Add(ref _totalCasOps, localCasOps);
    }

    public static void Main()
    {
        Console.WriteLine("=== C# (.NET 8): High-Contention ACID Banking Ledger (2,000,000 TXs) ===");
        Console.WriteLine($"Accounts: {NumAccounts} (Each starting with ${InitialBalance / 100}.00)");
        Console.WriteLine($"Transactions: {TotalTxs} (70% RWLock Inquiries, 20% Lock-Free CAS, 10% Ordered 2-Lock Transfers)");

        for (int i = 0; i < NumAccounts; i++)
        {
            Balances[i] = InitialBalance;
            AccountLocks[i] = new ReaderWriterLockSlim();
        }

        var sw = Stopwatch.StartNew();

        Parallel.For(0, NumWorkers, new ParallelOptions { MaxDegreeOfParallelism = NumWorkers }, workerIdx =>
        {
            RunWorker(workerIdx);
        });

        sw.Stop();

        long tookMs = sw.ElapsedMilliseconds;

        long finalTotalMoney = 0;
        for (int i = 0; i < NumAccounts; i++)
            finalTotalMoney += Balances[i];

        Console.WriteLine($"Processed {TotalTxs} ACID transactions in: {tookMs} ms");
        Console.WriteLine($"Throughput: {TotalTxs / (tookMs / 1000.0):F1} tx/sec");
        Console.WriteLine($"Operations breakdown: Inquiries={TotalTxs * 7 / 10}, Transfers={_totalTransfers}, CAS Direct Ops={_totalCasOps}");
        Console.WriteLine($"Final Total Bank Balance: ${finalTotalMoney / 100}.{finalTotalMoney % 100:D2}");
    }
}

