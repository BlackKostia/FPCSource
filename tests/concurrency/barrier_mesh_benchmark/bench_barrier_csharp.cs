using System;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

public class Program
{
    private const int Rows = 1000;
    private const int Cols = 2000;
    private const int NumWorkers = 12;
    private const int TotalPhases = 50;

    private static int[,] _gridA = new int[Rows, Cols];
    private static int[,] _gridB = new int[Rows, Cols];
    private static int[,] _currGrid = _gridA;
    private static int[,] _nextGrid = _gridB;

    private static Barrier _barrier = null!;

    private static void SwapGrids(Barrier b)
    {
        var tmp = _currGrid;
        _currGrid = _nextGrid;
        _nextGrid = tmp;
    }

    private static void RunWorker(int workerIdx)
    {
        int rowsPerWorker = (Rows - 2) / NumWorkers;
        int startRow = 1 + workerIdx * rowsPerWorker;
        int endRow = (workerIdx == NumWorkers - 1) ? Rows - 2 : startRow + rowsPerWorker - 1;

        for (int phase = 1; phase <= TotalPhases; phase++)
        {
            var curr = _currGrid;
            var next = _nextGrid;

            for (int r = startRow; r <= endRow; r++)
            {
                for (int c = 1; c <= Cols - 2; c++)
                {
                    int sumNeighbors = curr[r - 1, c] + curr[r + 1, c] +
                                      curr[r, c - 1] + curr[r, c + 1];
                    next[r, c] = sumNeighbors / 4;
                }
            }

            _barrier.SignalAndWait();
        }
    }

    public static void Main()
    {
        Console.WriteLine("=== C# (.NET 8): 2D Numerical Mesh with Barrier ===");
        Console.WriteLine($"Grid size: {Rows} x {Cols} = {Rows * Cols} cells");
        Console.WriteLine($"Total phases: {TotalPhases} ({(long)Rows * Cols * TotalPhases} total cell updates across {NumWorkers} workers)");

        for (int c = 0; c < Cols; c++)
        {
            _gridA[0, c] = 10000;
            _gridA[Rows - 1, c] = 10000;
            _gridB[0, c] = 10000;
            _gridB[Rows - 1, c] = 10000;
        }

        for (int r = 450; r <= 550; r++)
            for (int c = 950; c <= 1050; c++)
                _gridA[r, c] = 50000;

        _barrier = new Barrier(NumWorkers, SwapGrids);

        var sw = Stopwatch.StartNew();

        var tasks = new Task[NumWorkers];
        for (int i = 0; i < NumWorkers; i++)
        {
            int wIdx = i;
            tasks[i] = Task.Run(() => RunWorker(wIdx));
        }

        Task.WaitAll(tasks);
        sw.Stop();

        long tookMs = sw.ElapsedMilliseconds;

        long totalChecksum = 0;
        for (int r = 0; r < Rows; r++)
            for (int c = 0; c < Cols; c++)
                totalChecksum += _currGrid[r, c];

        Console.WriteLine($"Completed {TotalPhases} lockstep phases in: {tookMs} ms");
        Console.WriteLine($"Throughput: {((double)Rows * Cols * TotalPhases) / (tookMs / 1000.0):F1} cell-updates/sec");
        Console.WriteLine($"Final grid energy checksum: {totalChecksum}");
    }
}

