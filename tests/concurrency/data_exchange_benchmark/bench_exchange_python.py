import time
import threading
import queue

TOTAL_TRANSACTIONS = 1000000
NUM_PRODUCERS = 6
NUM_WORKERS = 6
BUFFER_CAPACITY = 50000

inbound_queue = queue.Queue(maxsize=BUFFER_CAPACITY)
outbound_queue = queue.Queue(maxsize=BUFFER_CAPACITY)

total_confirmed = 0
total_fees = 0
audit_checksum = 0

def compute_hash(tx_id: int, amount: int) -> int:
    h = (tx_id ^ (amount << 16)) & 0xFFFFFFFFFFFFFFFF
    for _ in range(20):
        h = (h * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
    return h

def producer(idx: int):
    chunk = TOTAL_TRANSACTIONS // NUM_PRODUCERS
    start_i = idx * chunk + 1
    end_i = TOTAL_TRANSACTIONS + 1 if idx == NUM_PRODUCERS - 1 else (idx + 1) * chunk + 1

    for i in range(start_i, end_i):
        tx = (i, (i % 10000) + 1, ((i + 42) % 10000) + 1, (i % 5000) + 10)
        inbound_queue.put(tx)

def worker():
    while True:
        tx = inbound_queue.get()
        if tx is None:
            inbound_queue.task_done()
            break
        tx_id, acc_from, acc_to, amount = tx
        fee = (amount * 15) // 10000
        sig = compute_hash(tx_id, amount)
        outbound_queue.put((tx_id, 1, fee, sig))
        inbound_queue.task_done()

def auditor():
    global total_confirmed, total_fees, audit_checksum
    while True:
        conf = outbound_queue.get()
        if conf is None:
            outbound_queue.task_done()
            break
        tx_id, status, fee, sig = conf
        total_confirmed += 1
        total_fees += fee
        audit_checksum ^= sig
        outbound_queue.task_done()

if __name__ == "__main__":
    print("=== Python: Queue Pipeline Data Exchange (1,000,000 txs) ===")
    print(f"Producers: {NUM_PRODUCERS}, Workers: {NUM_WORKERS}, Auditor: 1")

    t_audit = threading.Thread(target=auditor)
    t_audit.start()

    workers = [threading.Thread(target=worker) for _ in range(NUM_WORKERS)]
    for w in workers:
        w.start()

    t0 = time.time()

    producers = [threading.Thread(target=producer, args=(i,)) for i in range(NUM_PRODUCERS)]
    for p in producers:
        p.start()
    for p in producers:
        p.join()

    # Signal workers to finish
    for _ in range(NUM_WORKERS):
        inbound_queue.put(None)
    for w in workers:
        w.join()

    # Signal auditor to finish
    outbound_queue.put(None)
    t_audit.join()

    took = time.time() - t0
    took_ms = int(took * 1000)

    print(f"Successfully processed & exchanged {total_confirmed} transactions!")
    print(f"Execution time: {took_ms} ms")
    print(f"Throughput: {TOTAL_TRANSACTIONS / took:.1f} tx/sec")
    print(f"Total data transfers: {total_confirmed * 2} items across threads")
    print(f"Total fees: ${total_fees // 100}.{total_fees % 100:02d}")
    print(f"Audit checksum: {audit_checksum}")

