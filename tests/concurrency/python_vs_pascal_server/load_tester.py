#!/usr/bin/env python3
import sys
import time
import socket
import threading
import statistics
import struct
import urllib.parse
from concurrent.futures import ThreadPoolExecutor

def send_http_request(host, port, method, path):
    t0 = time.perf_counter()
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))
    s.settimeout(5.0)
    try:
        s.connect((host, port))
        req = f"{method} {path} HTTP/1.1\r\nHost: {host}:{port}\r\nConnection: close\r\n\r\n"
        s.sendall(req.encode("utf-8"))
        chunks = []
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            chunks.append(chunk)
        resp = b"".join(chunks)
        t1 = time.perf_counter()
        latency_ms = (t1 - t0) * 1000.0
        success = b"200 OK" in resp
        return success, latency_ms
    except Exception as e:
        t1 = time.perf_counter()
        return False, (t1 - t0) * 1000.0
    finally:
        s.close()

def run_benchmark(target_port, total_requests=10000, concurrency=50, work_n=1500):
    host = "127.0.0.1"
    print(f"Starting load test on {host}:{target_port} -> Total Requests: {total_requests}, Concurrency: {concurrency}, Work N: {work_n}...")

    # Warmup with 100 requests
    for i in range(100):
        send_http_request(host, target_port, "GET", f"/set?key=item_{i}&val=init_{i}")

    requests_workload = []
    for i in range(total_requests):
        m = i % 20
        if m < 12: # 60% reads
            requests_workload.append(("GET", f"/get?key=item_{i % 100}"))
        elif m < 16: # 20% writes
            requests_workload.append(("POST", f"/set?key=item_{i % 100}&val=payload_{i}"))
        elif m < 19: # 15% compute
            requests_workload.append(("GET", f"/work?n={work_n}"))
        else: # 5% stats
            requests_workload.append(("GET", "/stats"))

    latencies = []
    successes = 0
    failures = 0

    t_start = time.perf_counter()

    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [executor.submit(send_http_request, host, target_port, meth, p) for (meth, p) in requests_workload]
        for f in futures:
            ok, lat = f.result()
            latencies.append(lat)
            if ok:
                successes += 1
            else:
                failures += 1

    t_end = time.perf_counter()
    total_time = t_end - t_start
    rps = total_requests / total_time if total_time > 0 else 0

    latencies.sort()
    avg_lat = statistics.mean(latencies)
    med_lat = statistics.median(latencies)
    p90_lat = latencies[int(len(latencies) * 0.90)]
    p99_lat = latencies[int(len(latencies) * 0.99)]
    min_lat = min(latencies)
    max_lat = max(latencies)

    print(f"Finished in {total_time:.2f} s")
    print(f"RPS: {rps:.2f} req/s")
    print(f"Success: {successes}, Failures: {failures}")
    print(f"Latency Avg: {avg_lat:.2f} ms, Med: {med_lat:.2f} ms, P90: {p90_lat:.2f} ms, P99: {p99_lat:.2f} ms")

    return {
        "port": target_port,
        "total_requests": total_requests,
        "concurrency": concurrency,
        "work_n": work_n,
        "total_time_s": round(total_time, 3),
        "rps": round(rps, 1),
        "success": successes,
        "failures": failures,
        "latency_avg_ms": round(avg_lat, 2),
        "latency_median_ms": round(med_lat, 2),
        "latency_p90_ms": round(p90_lat, 2),
        "latency_p99_ms": round(p99_lat, 2),
        "latency_min_ms": round(min_lat, 2),
        "latency_max_ms": round(max_lat, 2)
    }

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9001
    total = int(sys.argv[2]) if len(sys.argv) > 2 else 10000
    concurr = int(sys.argv[3]) if len(sys.argv) > 3 else 50
    work_n = int(sys.argv[4]) if len(sys.argv) > 4 else 1500
    res = run_benchmark(port, total, concurr, work_n)
    import json
    print("\n--- JSON RESULT ---")
    print(json.dumps(res))

