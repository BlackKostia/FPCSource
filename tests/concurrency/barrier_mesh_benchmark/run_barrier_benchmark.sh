#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/tests/concurrency/fpcenv.sh"

echo "======================================================================"
echo "   TEST 2: MULTI-PHASE 2D MESH BARRIER BENCHMARK (100,000,000 CELLS)   "
echo "======================================================================"
echo "Grid: 1,000 x 2,000 = 2,000,000 cells per phase x 50 lockstep phases"
echo "Metrics: Wall Clock Time, Throughput, User CPU, Sys CPU, CPU %, Context Switches, Max RSS"
echo "======================================================================"
echo ""

# Compile Pascal
$FPC_TRUNK @"$FPC_CFG" -FE"$SCRIPT_DIR" "$SCRIPT_DIR/bench_barrier_modern.pp" > /dev/null
$FPC_TRUNK @"$FPC_CFG" -FE"$SCRIPT_DIR" "$SCRIPT_DIR/bench_barrier_classic.pp" > /dev/null

run_barrier() {
    local NAME="$1"
    local CMD="$2"
    local LOG="/tmp/profile_barrier_${NAME}.log"
    echo "----------------------------------------------------------------------"
    echo ">>> Running: $NAME"
    echo "----------------------------------------------------------------------"
    /usr/bin/time -v $CMD 2> "$LOG"
    echo ""
    echo "--- System & CPU Metrics for $NAME ---"
    grep "Percent of CPU this job got" "$LOG"
    grep "User time (seconds)" "$LOG"
    grep "System time (seconds)" "$LOG"
    grep "Elapsed (wall clock) time" "$LOG"
    grep "Maximum resident set size" "$LOG"
    grep "Voluntary context switches" "$LOG"
    grep "Involuntary context switches" "$LOG"
    echo ""
}

run_barrier "Modern_Pascal" "$SCRIPT_DIR/bench_barrier_modern"
run_barrier "Classic_Pascal" "$SCRIPT_DIR/bench_barrier_classic"
run_barrier "CSharp_DotNet8" "dotnet $SCRIPT_DIR/bin/Release/net8.0/bench_barrier_csharp.dll"
run_barrier "Python" "python3 $SCRIPT_DIR/bench_barrier_python.py"

echo "======================================================================"
echo "                     CODE COMPLEXITY COMPARISON (LoC)                 "
echo "======================================================================"
wc -l "$SCRIPT_DIR/bench_barrier_modern.pp" \
      "$SCRIPT_DIR/bench_barrier_classic.pp" \
      "$SCRIPT_DIR/bench_barrier_csharp.cs" \
      "$SCRIPT_DIR/bench_barrier_python.py"
echo "======================================================================"

