#!/bin/sh
# Збирає й запускає тести розумних вказівників (rtl-objpas/smartptrs) з джерел гілки.
# Використання: build-smartptrs.sh [вихідна_тека] [додаткові опції компілятора]
# Приклад перевірки витоків: build-smartptrs.sh "" -gh
set -e
. "$(dirname "$0")/fpcenv.sh"
OUT="${1:-$ROOT/tests/concurrency/out-smartptrs}"
[ $# -gt 0 ] && shift
mkdir -p "$OUT"
rm -f "$OUT"/*.ppu "$OUT"/*.o
# Лише smartptrs компілюється з джерел: решта rtl-objpas береться зібраною.
"$FPC_TRUNK" @"$FPC_CFG" -gl -Sa "$@" -FU"$OUT" \
  "$ROOT/packages/rtl-objpas/src/inc/smartptrs.pp"
"$FPC_TRUNK" @"$FPC_CFG" -gl -Sa "$@" -FU"$OUT" -FE"$OUT" -Fu"$OUT" \
  -Fu"$ROOT/packages/rtl-objpas/tests" \
  "$ROOT/tests/concurrency/test_smartptrs.pp"
rm -f "$FPC_CFG"
echo "Готово: $OUT/test_smartptrs"
"$OUT/test_smartptrs" --all --format=plain
