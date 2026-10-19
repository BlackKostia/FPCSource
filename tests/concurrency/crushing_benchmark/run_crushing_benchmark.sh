#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/tests/concurrency/fpcenv.sh"

echo "======================================================================"
echo "         CRUSHING CONCURRENCY BENCHMARK SUITE (2,000,000 OPS)         "
echo "======================================================================"
echo "Scenario: Financial Trading & Analytics Cache Pipeline"
echo "  - 2,000,000 operations across 12 concurrent workers"
echo "  - 90% Read queries (cache inspection & portfolio risk valuation)"
echo "  - 10% Write updates + Event streaming to Consumer queue/channel"
echo "======================================================================"
echo ""

# 1. Modern Free Pascal
echo ">>> [1/3] Compiling and running Modern Free Pascal..."
$FPC_TRUNK @"$FPC_CFG" -FE"$SCRIPT_DIR" "$SCRIPT_DIR/bench_modern_pascal.pp" > /dev/null
"$SCRIPT_DIR/bench_modern_pascal"
echo ""

# 2. Classic Free Pascal
echo ">>> [2/3] Compiling and running Classic Free Pascal..."
$FPC_TRUNK @"$FPC_CFG" -FE"$SCRIPT_DIR" "$SCRIPT_DIR/bench_classic_pascal.pp" > /dev/null
"$SCRIPT_DIR/bench_classic_pascal"
echo ""

# 3. Python
echo ">>> [3/3] Running Python (GIL-bound multi-threaded)..."
python3 "$SCRIPT_DIR/bench_python.py"
echo ""

# 4. Summary LoC
echo "======================================================================"
echo "                     CODE COMPLEXITY COMPARISON (LoC)                 "
echo "======================================================================"
wc -l "$SCRIPT_DIR/bench_modern_pascal.pp" \
      "$SCRIPT_DIR/bench_classic_pascal.pp" \
      "$SCRIPT_DIR/bench_python.py" \
      "$SCRIPT_DIR/bench_csharp.cs"
echo "======================================================================"

