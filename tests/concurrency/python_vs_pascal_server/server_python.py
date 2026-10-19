#!/usr/bin/env python3
import socket
import threading
import time
import json
import urllib.parse
from queue import Queue

PORT = 9001
HOST = "127.0.0.1"

# Shared in-memory cache protected by a Lock
cache = {}
cache_lock = threading.Lock()

# Statistics
stats = {
    "requests": 0,
    "reads": 0,
    "writes": 0,
    "computes": 0,
    "start_time": time.time()
}
stats_lock = threading.Lock()

# Background logging queue (channel)
log_queue = Queue(maxsize=100000)

def background_logger():
    count = 0
    while True:
        try:
            entry = log_queue.get()
            if entry is None:
                break
            count += 1
            log_queue.task_done()
        except Exception:
            pass

logger_thread = threading.Thread(target=background_logger, daemon=True)
logger_thread.start()

def compute_work(n):
    # Mathematical CPU work (XOR checksum)
    s = 0
    for i in range(n):
        s ^= (i * 37) & 0xFFFFFFFF
    return s

def handle_client(conn, addr):
    try:
        data = conn.recv(4096)
        if not data:
            return
        
        request_text = data.decode("utf-8", errors="replace")
        lines = request_text.split("\r\n")
        if not lines:
            return
        parts = lines[0].split(" ")
        if len(parts) < 2:
            return
        method, full_path = parts[0], parts[1]
        
        parsed = urllib.parse.urlparse(full_path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        status_code = 200
        status_text = "OK"
        response_data = {}

        if path == "/stats":
            with stats_lock:
                reqs = stats["requests"]
                reads = stats["reads"]
                writes = stats["writes"]
                comps = stats["computes"]
                uptime = time.time() - stats["start_time"]
            with cache_lock:
                cache_size = len(cache)
            response_data = {
                "server": "Python Multithreaded",
                "uptime_s": round(uptime, 2),
                "total_requests": reqs,
                "reads": reads,
                "writes": writes,
                "computes": comps,
                "cache_size": cache_size,
                "log_queue_size": log_queue.qsize()
            }
        elif path == "/get":
            key = query.get("key", [""])[0]
            with cache_lock:
                val = cache.get(key, None)
            with stats_lock:
                stats["requests"] += 1
                stats["reads"] += 1
            response_data = {"key": key, "val": val, "found": val is not None}
        elif path == "/set":
            key = query.get("key", [""])[0]
            val = query.get("val", [""])[0]
            with cache_lock:
                cache[key] = val
            with stats_lock:
                stats["requests"] += 1
                stats["writes"] += 1
            response_data = {"key": key, "val": val, "status": "stored"}
        elif path == "/work":
            n = int(query.get("n", [1000])[0])
            result = compute_work(n)
            with stats_lock:
                stats["requests"] += 1
                stats["computes"] += 1
            response_data = {"work_n": n, "result": result}
        else:
            status_code = 404
            status_text = "Not Found"
            response_data = {"error": "Not Found"}

        # Push to background logger queue
        try:
            log_queue.put_nowait((time.time(), method, path, status_code))
        except Exception:
            pass

        body = json.dumps(response_data).encode("utf-8")
        resp = (
            f"HTTP/1.1 {status_code} {status_text}\r\n"
            f"Content-Type: application/json\r\n"
            f"Content-Length: {len(body)}\r\n"
            f"Connection: close\r\n"
            f"\r\n"
        ).encode("utf-8") + body
        conn.sendall(resp)
    finally:
        conn.close()

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((HOST, PORT))
    s.listen(8192)
    print(f"Python multithreaded server listening on port {PORT}...", flush=True)
    while True:
        try:
            conn, addr = s.accept()
            t = threading.Thread(target=handle_client, args=(conn, addr), daemon=True)
            t.start()
        except KeyboardInterrupt:
            break
        except Exception as e:
            pass

if __name__ == "__main__":
    main()
