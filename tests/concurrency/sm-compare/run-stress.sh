#!/bin/bash
# 15 paired await stress tests. Pascal {$ASYNCMODE STATEMACHINE} and C# async/await.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
OUT="$DIR/out"
mkdir -p "$OUT"

. "$ROOT/tests/concurrency/fpcenv.sh"
echo "=== Pascal ==="
"$FPC_TRUNK" @"$FPC_CFG" -FE"$OUT" -FU"$OUT" "$DIR/pascal/stress15.pp"
pascal_rc=0
"$OUT/stress15" | tee "$OUT/pascal-stress.txt" || pascal_rc=$?

echo "=== C# ==="
csharp_rc=0
dotnet run --project "$DIR/csharp/stress/Stress15.csproj" -c Release --nologo | tee "$OUT/csharp-stress.txt" || csharp_rc=$?

if [ "$pascal_rc" -ne 0 ] || [ "$csharp_rc" -ne 0 ]; then
  exit 1
fi
