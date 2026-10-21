#!/bin/bash
# 20 paired state-machine tests: Pascal {$ASYNCMODE STATEMACHINE} and C# async/await.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
OUT="$DIR/out"
mkdir -p "$OUT"

. "$ROOT/tests/concurrency/fpcenv.sh"
echo "=== Pascal ==="
"$FPC_TRUNK" @"$FPC_CFG" -FE"$OUT" -FU"$OUT" "$DIR/pascal/sm20.pp"
"$OUT/sm20" | tee "$OUT/pascal.txt"

echo "=== C# ==="
dotnet run --project "$DIR/csharp/Sm20.csproj" -c Release --nologo | tee "$OUT/csharp.txt"
