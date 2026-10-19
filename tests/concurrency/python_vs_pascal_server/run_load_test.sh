#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"

echo "=========================================================="
echo "    BENCHMARK: 200,000 REQUESTS LOAD TEST SUITE           "
echo "    Classic Pascal vs Python vs Modern Free Pascal (MFPC) "
echo "=========================================================="

# Cleanup any stray servers
fuser -k 9001/tcp 2>/dev/null || true
fuser -k 9002/tcp 2>/dev/null || true
fuser -k 9003/tcp 2>/dev/null || true
sleep 1

TOTAL_REQS=${1:-200000}
CONCURR=${2:-150}
WORK_N=${3:-1000}

echo "Parameters: Total Requests=$TOTAL_REQS, Concurrency=$CONCURR, Work N=$WORK_N"

# Ensure binaries are built
if [ ! -f "$DIR/server_pascal" ]; then
  echo "Building Modern Pascal server..."
  . "$ROOT/tests/concurrency/fpcenv.sh"
  $FPC_TRUNK @"$FPC_CFG" -FE"$DIR" "$DIR/server_pascal.pp"
fi

if [ ! -f "$DIR/server_pascal_classic" ]; then
  echo "Building Classic Pascal server..."
  . "$ROOT/tests/concurrency/fpcenv.sh"
  $FPC_TRUNK @"$FPC_CFG" -FE"$DIR" "$DIR/server_pascal_classic.pp"
fi

# 1. TEST CLASSIC PASCAL SERVER (Port 9003)
echo ""
echo "=========================================================="
echo ">>> [1/3] Testing Classic Free Pascal Server (port 9003)..."
echo "=========================================================="
"$DIR/server_pascal_classic" &
CLASSIC_PID=$!

for i in {1..30}; do
  if curl -s http://127.0.0.1:9003/stats > /dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

echo "Classic Pascal running (PID: $CLASSIC_PID). Starting load test..."
python3 "$DIR/load_tester.py" 9003 "$TOTAL_REQS" "$CONCURR" "$WORK_N" | tee "$DIR/classic_run.log"

CLASSIC_MEM=$(ps -p $CLASSIC_PID -o rss= 2>/dev/null || echo "0")
CLASSIC_MEM_MB=$(awk "BEGIN {print $CLASSIC_MEM / 1024}")
echo "Classic Pascal Final RSS Memory: ${CLASSIC_MEM_MB} MB"

kill -9 $CLASSIC_PID 2>/dev/null || true
wait $CLASSIC_PID 2>/dev/null || true
sleep 1

# 2. TEST PYTHON MULTITHREADED SERVER (Port 9001)
echo ""
echo "=========================================================="
echo ">>> [2/3] Testing Python Multithreaded Server (port 9001)..."
echo "=========================================================="
python3 "$DIR/server_python.py" &
PY_PID=$!

for i in {1..30}; do
  if curl -s http://127.0.0.1:9001/stats > /dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

echo "Python server running (PID: $PY_PID). Starting load test..."
python3 "$DIR/load_tester.py" 9001 "$TOTAL_REQS" "$CONCURR" "$WORK_N" | tee "$DIR/python_run.log"

PY_MEM=$(ps -p $PY_PID -o rss= 2>/dev/null || echo "0")
PY_MEM_MB=$(awk "BEGIN {print $PY_MEM / 1024}")
echo "Python Final RSS Memory: ${PY_MEM_MB} MB"

kill -9 $PY_PID 2>/dev/null || true
wait $PY_PID 2>/dev/null || true
sleep 1

# 3. TEST MODERN FREE PASCAL SERVER (Port 9002)
echo ""
echo "=========================================================="
echo ">>> [3/3] Testing Modern Free Pascal Server (port 9002)..."
echo "=========================================================="
"$DIR/server_pascal" &
PAS_PID=$!

for i in {1..30}; do
  if curl -s http://127.0.0.1:9002/stats > /dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

echo "Modern Pascal server running (PID: $PAS_PID). Starting load test..."
python3 "$DIR/load_tester.py" 9002 "$TOTAL_REQS" "$CONCURR" "$WORK_N" | tee "$DIR/pascal_run.log"

PAS_MEM=$(ps -p $PAS_PID -o rss= 2>/dev/null || echo "0")
PAS_MEM_MB=$(awk "BEGIN {print $PAS_MEM / 1024}")
echo "Modern Pascal Final RSS Memory: ${PAS_MEM_MB} MB"

kill -9 $PAS_PID 2>/dev/null || true
wait $PAS_PID 2>/dev/null || true

echo ""
echo "=========================================================="
echo "               200,000 BENCHMARK COMPLETE                 "
echo "=========================================================="
