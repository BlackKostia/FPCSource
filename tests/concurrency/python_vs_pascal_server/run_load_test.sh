#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"

echo "=========================================================="
echo "    BENCHMARK: MULTITHREADED PYTHON VS MODERN PASCAL      "
echo "=========================================================="

# Cleanup any stray servers
fuser -k 9001/tcp 2>/dev/null || true
fuser -k 9002/tcp 2>/dev/null || true
sleep 1

# 1. TEST PYTHON SERVER
echo ""
echo ">>> [1/2] Launching Python Multithreaded Server (port 9001)..."
python3 "$DIR/server_python.py" &
PY_PID=$!

# Wait for readiness
for i in {1..30}; do
  if curl -s http://127.0.0.1:9001/stats > /dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

echo "Python server running (PID: $PY_PID). Starting load test..."
python3 "$DIR/load_tester.py" 9001 10000 50 | tee "$DIR/python_run.log"

PY_MEM=$(ps -p $PY_PID -o rss= 2>/dev/null || echo "0")
PY_MEM_MB=$(awk "BEGIN {print $PY_MEM / 1024}")
echo "Python Final RSS Memory: ${PY_MEM_MB} MB"

kill -9 $PY_PID 2>/dev/null || true
wait $PY_PID 2>/dev/null || true
sleep 1

# 2. TEST PASCAL SERVER
echo ""
echo ">>> [2/2] Launching Modern Free Pascal Server (port 9002)..."
"$DIR/server_pascal" &
PAS_PID=$!

# Wait for readiness
for i in {1..30}; do
  if curl -s http://127.0.0.1:9002/stats > /dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

echo "Modern Pascal server running (PID: $PAS_PID). Starting load test..."
python3 "$DIR/load_tester.py" 9002 10000 50 | tee "$DIR/pascal_run.log"

PAS_MEM=$(ps -p $PAS_PID -o rss= 2>/dev/null || echo "0")
PAS_MEM_MB=$(awk "BEGIN {print $PAS_MEM / 1024}")
echo "Pascal Final RSS Memory: ${PAS_MEM_MB} MB"

kill -9 $PAS_PID 2>/dev/null || true
wait $PAS_PID 2>/dev/null || true

echo ""
echo "=========================================================="
echo "                   BENCHMARK COMPLETE                     "
echo "=========================================================="
