#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

source "$REPO_ROOT/tests/concurrency/fpcenv.sh"

echo "======================================================================"
echo "    TEST 3: HIGH-CONTENTION ACID BANKING BENCHMARK (2,000,000 TXS)    "
echo "======================================================================"
echo "Topology: 500 Accounts, 12 Workers, 70% Inquiries, 20% CAS, 10% 2-Lock Transfers"
echo "Metrics: Wall Clock Time, Throughput, User CPU, Sys CPU, CPU %, Context Switches, Max RSS"
echo "======================================================================"
echo ""

# Compile Pascal
$FPC_TRUNK @"$FPC_CFG" -FE"$SCRIPT_DIR" "$SCRIPT_DIR/bench_acid_modern.pp" > /dev/null
$FPC_TRUNK @"$FPC_CFG" -FE"$SCRIPT_DIR" "$SCRIPT_DIR/bench_acid_classic.pp" > /dev/null

run_acid() {
    local NAME="$1"
    local CMD="$2"
    local LOG="/tmp/profile_acid_${NAME}.log"
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

run_acid "Modern_Pascal" "$SCRIPT_DIR/bench_acid_modern"
run_acid "Classic_Pascal" "$SCRIPT_DIR/bench_acid_classic"
run_acid "CSharp_DotNet8" "dotnet $SCRIPT_DIR/bin/Release/net8.0/bench_acid_csharp.dll"
run_acid "Python" "python3 $SCRIPT_DIR/bench_acid_python.py"

echo "======================================================================"
echo "                     CODE COMPLEXITY COMPARISON (LoC)                 "
echo "======================================================================"
wc -l "$SCRIPT_DIR/bench_acid_modern.pp" \
      "$SCRIPT_DIR/bench_acid_classic.pp" \
      "$SCRIPT_DIR/bench_acid_csharp.cs" \
      "$SCRIPT_DIR/bench_acid_python.py"
echo "======================================================================"
