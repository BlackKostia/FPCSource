#!/usr/bin/env python3
import asyncio
import time
import os
import resource

COUNT = 100000

counter = 0

async def worker(idx):
    global counter
    await asyncio.sleep(0) # Cooperative yield
    counter += 1

async def main():
    global counter
    print(f"=== Python (asyncio): 100,000 Concurrent Coroutines ===")
    t0 = time.perf_counter()
    
    tasks = [asyncio.create_task(worker(i)) for i in range(COUNT)]
    await asyncio.gather(*tasks)
    
    t1 = time.perf_counter()
    mem_kb = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    
    print(f"Executed {COUNT} coroutines in: {(t1 - t0)*1000:.2f} ms")
    print(f"Counter: {counter}")
    print(f"Peak RSS Memory: {mem_kb / 1024:.2f} MB")

if __name__ == "__main__":
    asyncio.run(main())
