import time
import threading
import queue

TOTAL_MESSAGES = 2000000
NUM_PRODUCERS = 4
NUM_SHARDS = 4
INGEST_CAPACITY = 50000
SHARD_CAPACITY = 25000
OUTBOUND_CAPACITY = 50000

ingest_queue = queue.Queue(maxsize=INGEST_CAPACITY)
shard_queues = [queue.Queue(maxsize=SHARD_CAPACITY) for _ in range(NUM_SHARDS)]
outbound_queue = queue.Queue(maxsize=OUTBOUND_CAPACITY)

total_aggregated = 0
total_fees = 0
aggregator_checksum = 0

def compute_risk_signature(msg_id: int, amount: int, shard_id: int) -> int:
    h = (msg_id ^ (amount << 16) ^ (shard_id * 7919)) & 0xFFFFFFFFFFFFFFFF
    for _ in range(20):
        h = (h * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
    return h

def producer(prod_idx: int):
    chunk = TOTAL_MESSAGES // NUM_PRODUCERS
    start_i = prod_idx * chunk + 1
    end_i = TOTAL_MESSAGES + 1 if prod_idx == NUM_PRODUCERS - 1 else (prod_idx + 1) * chunk + 1

    for i in range(start_i, end_i):
        msg = (i, (i % 100000) + 1, (i % 5000) + 10, i * 1337)
        ingest_queue.put(msg)

def router():
    while True:
        msg = ingest_queue.get()
        if msg is None:
            ingest_queue.task_done()
            break
        shard_idx = msg[1] % NUM_SHARDS
        shard_queues[shard_idx].put(msg)
        ingest_queue.task_done()

    for s in range(NUM_SHARDS):
        shard_queues[s].put(None)

def shard_worker(shard_idx: int):
    q = shard_queues[shard_idx]
    while True:
        msg = q.get()
        if msg is None:
            q.task_done()
            break
        msg_id, account_id, amount, payload = msg
        fee = (amount * 15) // 10000
        sig = compute_risk_signature(msg_id, amount, shard_idx)
        outbound_queue.put((msg_id, shard_idx, fee, sig))
        q.task_done()

def aggregator():
    global total_aggregated, total_fees, aggregator_checksum
    while True:
        enriched = outbound_queue.get()
        if enriched is None:
            outbound_queue.task_done()
            break
        msg_id, shard_idx, fee, sig = enriched
        total_aggregated += 1
        total_fees += fee
        aggregator_checksum ^= sig
        outbound_queue.task_done()

if __name__ == "__main__":
    print("=== Python: DAG Actor Pipeline (2,000,000 Messages) ===")
    print("Topology: 4 Producers -> IngestQueue -> Router -> 4 ShardQueues -> 4 Workers -> OutboundQueue -> Aggregator")

    t_agg = threading.Thread(target=aggregator)
    t_agg.start()

    workers = [threading.Thread(target=shard_worker, args=(s,)) for s in range(NUM_SHARDS)]
    for w in workers:
        w.start()

    t_router = threading.Thread(target=router)
    t_router.start()

    t0 = time.time()

    producers = [threading.Thread(target=producer, args=(p,)) for p in range(NUM_PRODUCERS)]
    for p in producers:
        p.start()
    for p in producers:
        p.join()

    # Producers done -> stop router
    ingest_queue.put(None)
    t_router.join()

    # Workers stop when router puts None in all shard queues
    for w in workers:
        w.join()

    # Workers done -> stop aggregator
    outbound_queue.put(None)
    t_agg.join()

    took = time.time() - t0
    took_ms = int(took * 1000)

    print(f"Successfully processed DAG through all stages: {total_aggregated} messages")
    print(f"Total execution time: {took_ms} ms")
    print(f"Throughput: {TOTAL_MESSAGES / took:.1f} msgs/sec")
    print(f"Total fees: ${total_fees // 100}.{total_fees % 100:02d}")
    print(f"Aggregator checksum: {aggregator_checksum}")

