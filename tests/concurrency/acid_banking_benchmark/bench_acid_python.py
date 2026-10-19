import time
import threading

TOTAL_TXS = 2000000
NUM_ACCOUNTS = 500
NUM_WORKERS = 12
INITIAL_BALANCE = 1000000

balances = [INITIAL_BALANCE] * NUM_ACCOUNTS
account_locks = [threading.Lock() for _ in range(NUM_ACCOUNTS)]

total_inquiries = 0
total_transfers = 0
total_cas_ops = 0
stats_lock = threading.Lock()

def worker(worker_idx: int):
    global total_inquiries, total_transfers, total_cas_ops
    chunk = TOTAL_TXS // NUM_WORKERS
    start_i = worker_idx * chunk + 1
    end_i = TOTAL_TXS + 1 if worker_idx == NUM_WORKERS - 1 else (worker_idx + 1) * chunk + 1

    local_inquiries = 0
    local_transfers = 0
    local_cas_ops = 0

    for i in range(start_i, end_i):
        op_type = i % 10
        acc_a = (i * 7919) % NUM_ACCOUNTS

        if op_type < 7:
            # 70% Inquiries
            with account_locks[acc_a]:
                read_val = balances[acc_a]
            local_inquiries += read_val & 1
        elif op_type < 9:
            # 20% Direct Update (in Python, done under account lock)
            amount = (i % 100) + 1
            with account_locks[acc_a]:
                if (i & 1) == 0:
                    balances[acc_a] += amount
                else:
                    balances[acc_a] -= amount
            local_cas_ops += 1
        else:
            # 10% Multi-Account Transfer: Ordered 2-Lock Acquisition
            acc_b = ((i * 1337) + 42) % NUM_ACCOUNTS
            if acc_a == acc_b:
                acc_b = (acc_a + 1) % NUM_ACCOUNTS

            first_lock = min(acc_a, acc_b)
            second_lock = max(acc_a, acc_b)

            with account_locks[first_lock]:
                with account_locks[second_lock]:
                    amount = (i % 250) + 10
                    if balances[acc_a] >= amount:
                        balances[acc_a] -= amount
                        balances[acc_b] += amount
                    local_transfers += 1

    with stats_lock:
        total_inquiries += local_inquiries
        total_transfers += local_transfers
        total_cas_ops += local_cas_ops

if __name__ == "__main__":
    print("=== Python: High-Contention ACID Banking Ledger (2,000,000 TXs) ===")
    print(f"Accounts: {NUM_ACCOUNTS} (Each starting with ${INITIAL_BALANCE // 100}.00)")
    print(f"Transactions: {TOTAL_TXS} (70% Inquiries, 20% Direct Ops, 10% Ordered 2-Lock Transfers)")

    t0 = time.time()
    threads = [threading.Thread(target=worker, args=(w,)) for w in range(NUM_WORKERS)]
    for t in threads: t.start()
    for t in threads: t.join()

    took = time.time() - t0
    took_ms = int(took * 1000)

    final_total_money = sum(balances)

    print(f"Processed {TOTAL_TXS} ACID transactions in: {took_ms} ms")
    print(f"Throughput: {TOTAL_TXS / took:.1f} tx/sec")
    print(f"Operations breakdown: Inquiries={TOTAL_TXS * 7 // 10}, Transfers={total_transfers}, CAS Direct Ops={total_cas_ops}")
    print(f"Final Total Bank Balance: ${final_total_money // 100}.{final_total_money % 100:02d}")

