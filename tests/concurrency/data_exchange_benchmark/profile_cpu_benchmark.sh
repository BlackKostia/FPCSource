#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/tests/concurrency/fpcenv.sh"

echo "======================================================================"
echo "    CPU UTILIZATION & PROFILING BENCHMARK (1,000,000 TRANSACTIONS)   "
echo "======================================================================"
echo "Measuring: User Time, Kernel Time, Multi-Core CPU %, Context Switches, RSS"
echo "======================================================================"
echo ""

# Compile Pascal binaries
echo "Compiling binaries..."
$FPC_TRUNK @"$FPC_CFG" -FE"$SCRIPT_DIR" "$SCRIPT_DIR/bench_exchange_modern.pp" > /dev/null
$FPC_TRUNK @"$FPC_CFG" -FE"$SCRIPT_DIR" "$SCRIPT_DIR/bench_exchange_classic.pp" > /dev/null
echo "Build complete."
echo ""

run_profile() {
    local NAME="$1"
    local CMD="$2"
    local LOG="/tmp/profile_${NAME}.log"
    echo "----------------------------------------------------------------------"
    echo ">>> Running Profile: $NAME"
    echo "----------------------------------------------------------------------"
    /usr/bin/time -v $CMD 2> "$LOG"
    echo ""
    echo "--- CPU & Resource Metrics for $NAME ---"
    grep "Percent of CPU this job got" "$LOG"
    grep "User time (seconds)" "$LOG"
    grep "System time (seconds)" "$LOG"
    grep "Elapsed (wall clock) time" "$LOG"
    grep "Maximum resident set size" "$LOG"
    grep "Voluntary context switches" "$LOG"
    grep "Involuntary context switches" "$LOG"
    echo ""
}

run_profile "Modern_Pascal" "$SCRIPT_DIR/bench_exchange_modern"
run_profile "Classic_Pascal" "$SCRIPT_DIR/bench_exchange_classic"
run_profile "CSharp_DotNet8" "dotnet $SCRIPT_DIR/bin/Release/net8.0/bench_exchange_csharp.dll"
run_profile "Python" "python3 $SCRIPT_DIR/bench_exchange_python.py"

echo "======================================================================"
echo "                   PROFILING RUN COMPLETED                            "
echo "======================================================================"

