import time
import threading
import queue

TOTAL_OPS = 500000
KEYS_COUNT = 1000
NUM_WORKERS = 12

cache = [(i + 1) * 100 for i in range(KEYS_COUNT)]
cache_lock = threading.Lock()
trade_queue = queue.Queue(maxsize=50000)

consumed_trades = 0
consumer_xor = 0
total_read_sum = 0
read_sum_lock = threading.Lock()

def compute_risk_hash(val: int, it: int) -> int:
    h = (val ^ it) & 0xFFFFFFFFFFFFFFFF
    for _ in range(30):
        h = (h * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
    return h

def consumer():
    global consumed_trades, consumer_xor
    while True:
        ev = trade_queue.get()
        if ev is None:
            break
        consumed_trades += 1
        consumer_xor ^= ev[2]

def worker(idx: int):
    global total_read_sum
    chunk_size = TOTAL_OPS // NUM_WORKERS
    start_i = idx * chunk_size
    end_i = TOTAL_OPS if idx == NUM_WORKERS - 1 else (idx + 1) * chunk_size

    local_read_sum = 0
    val = 0
    for i in range(start_i, end_i):
        key_id = i % KEYS_COUNT
        if i % 10 != 0:
            # 90% Reads
            with cache_lock:
                val = cache[key_id]
            local_read_sum += val ^ (i & 15)
        else:
            # 10% Writes + queue event
            with cache_lock:
                cache[key_id] = val + (i % 50)
                val = cache[key_id]
            ch = compute_risk_hash(val, i)
            trade_queue.put((key_id, val, ch))

    with read_sum_lock:
        total_read_sum += local_read_sum

if __name__ == "__main__":
    print("=== Python: threading.Lock + queue.Queue + threading.Thread ===")
    t_cons = threading.Thread(target=consumer)
    t_cons.start()

    t0 = time.time()

    workers = [threading.Thread(target=worker, args=(w,)) for w in range(NUM_WORKERS)]
    for w in workers:
        w.start()
    for w in workers:
        w.join()

    trade_queue.put(None)
    t_cons.join()

    took = time.time() - t0
    took_ms = int(took * 1000)

    print(f"Processed {TOTAL_OPS} ops in: {took_ms} ms")
    print(f"Throughput: {TOTAL_OPS / took:.1f} ops/sec")
    print(f"Consumed trade events: {consumed_trades}, Consumer XOR: {consumer_xor}")
    print(f"Total read sum: {total_read_sum}")
