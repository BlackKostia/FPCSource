#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/tests/concurrency/fpcenv.sh"

echo "======================================================================"
echo "    INTER-THREAD DATA EXCHANGE BENCHMARK (1,000,000 TRANSACTIONS)     "
echo "======================================================================"
echo "Architecture: Real-World Financial Transaction Pipeline"
echo "  - 6 Concurrent Producers generate 1,000,000 transaction records"
echo "  - Inbound Channel/Queue transfers records across threads"
echo "  - 6 Concurrent Workers validate, compute hash & calculate fees"
echo "  - Outbound Channel/Queue transfers confirmations across threads"
echo "  - 1 Auditor aggregates total confirmed volume and checksum"
echo "  - Total inter-thread data transfers: 2,000,000 items!"
echo "======================================================================"
echo ""

# 1. Modern Free Pascal
echo ">>> [1/3] Compiling and running Modern Free Pascal (TChannel<T> + TTask)..."
$FPC_TRUNK @"$FPC_CFG" -FE"$SCRIPT_DIR" "$SCRIPT_DIR/bench_exchange_modern.pp" > /dev/null
"$SCRIPT_DIR/bench_exchange_modern"
echo ""

# 2. Classic Free Pascal
echo ">>> [2/3] Compiling and running Classic Free Pascal (Manual Queues + TCriticalSection)..."
$FPC_TRUNK @"$FPC_CFG" -FE"$SCRIPT_DIR" "$SCRIPT_DIR/bench_exchange_classic.pp" > /dev/null
"$SCRIPT_DIR/bench_exchange_classic"
echo ""

# 3. Python
echo ">>> [3/3] Running Python (queue.Queue + 13 threads)..."
python3 "$SCRIPT_DIR/bench_exchange_python.py"
echo ""

# 4. Code complexity comparison
echo "======================================================================"
echo "                     CODE COMPLEXITY COMPARISON (LoC)                 "
echo "======================================================================"
wc -l "$SCRIPT_DIR/bench_exchange_modern.pp" \
      "$SCRIPT_DIR/bench_exchange_classic.pp" \
      "$SCRIPT_DIR/bench_exchange_python.py" \
      "$SCRIPT_DIR/bench_exchange_csharp.cs"
echo "======================================================================"

