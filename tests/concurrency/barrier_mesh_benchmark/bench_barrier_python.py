import time
import threading

ROWS = 1000
COLS = 2000
NUM_WORKERS = 12
TOTAL_PHASES = 50

# Flat 1D list or list of lists
grid_a = [0] * (ROWS * COLS)
grid_b = [0] * (ROWS * COLS)

for c in range(COLS):
    grid_a[c] = 10000
    grid_a[(ROWS - 1) * COLS + c] = 10000
    grid_b[c] = 10000
    grid_b[(ROWS - 1) * COLS + c] = 10000

for r in range(450, 551):
    for c in range(950, 1051):
        grid_a[r * COLS + c] = 50000

curr_grid = grid_a
next_grid = grid_b

def swap_grids():
    global curr_grid, next_grid
    curr_grid, next_grid = next_grid, curr_grid

barrier = threading.Barrier(NUM_WORKERS, action=swap_grids)

def worker(w_idx):
    rows_per_worker = (ROWS - 2) // NUM_WORKERS
    start_row = 1 + w_idx * rows_per_worker
    end_row = ROWS - 2 if w_idx == NUM_WORKERS - 1 else start_row + rows_per_worker - 1

    for phase in range(TOTAL_PHASES):
        curr = curr_grid
        nxt = next_grid

        for r in range(start_row, end_row + 1):
            row_idx = r * COLS
            for c in range(1, COLS - 1):
                idx = row_idx + c
                s = curr[idx - COLS] + curr[idx + COLS] + curr[idx - 1] + curr[idx + 1]
                nxt[idx] = s // 4

        barrier.wait()

if __name__ == "__main__":
    print("=== Python: 2D Numerical Mesh with Barrier ===")
    print(f"Grid size: {ROWS} x {COLS} = {ROWS * COLS} cells")
    print(f"Total phases: {TOTAL_PHASES} ({ROWS * COLS * TOTAL_PHASES} total cell updates across {NUM_WORKERS} workers)")

    t0 = time.time()
    threads = [threading.Thread(target=worker, args=(i,)) for i in range(NUM_WORKERS)]
    for t in threads: t.start()
    for t in threads: t.join()
    took = time.time() - t0
    took_ms = int(took * 1000)

    total_checksum = sum(curr_grid)
    print(f"Completed {TOTAL_PHASES} lockstep phases in: {took_ms} ms")
    print(f"Throughput: {((ROWS * COLS * TOTAL_PHASES) / took):.1f} cell-updates/sec")
    print(f"Final grid energy checksum: {total_checksum}")

