#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "=========================================================="
echo "   RUNNING MODERN PASCAL vs C# BENCHMARK SUITE (10/10)   "
echo "=========================================================="

. "$ROOT_DIR/tests/concurrency/fpcenv.sh"

PAS_DIR="$SCRIPT_DIR/pascal"
OUT_DIR="$SCRIPT_DIR/out"
mkdir -p "$OUT_DIR"

PAS_FILES=(
  "bench01_async_await.pp"
  "bench02_parallel_for.pp"
  "bench03_c100k_fibers.pp"
  "bench04_csp_channels.pp"
  "bench05_continuations.pp"
  "bench06_tuples.pp"
  "bench07_cancellation.pp"
  "bench08_slim_rwlock.pp"
  "bench09_generators.pp"
  "bench10_async_exceptions.pp"
)

PASSED=0
TOTAL=${#PAS_FILES[@]}

for FILE in "${PAS_FILES[@]}"; do
  NAME="${FILE%.pp}"
  echo ""
  echo "----------------------------------------------------------"
  echo ">>> Compiling and Running: $FILE"
  echo "----------------------------------------------------------"
  $FPC_TRUNK @"$FPC_CFG" -Fupackages/fcl-coroutines/src -FE"$OUT_DIR" "$PAS_DIR/$FILE"
  
  "$OUT_DIR/$NAME"
  echo ">>> Result: PASS"
  PASSED=$((PASSED + 1))
done

echo ""
echo "=========================================================="
echo "   ALL $PASSED / $TOTAL PASCAL BENCHMARKS COMPLETED AND PASSED! "
echo "=========================================================="

