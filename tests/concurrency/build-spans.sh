#!/bin/sh
# Збирає й запускає тести зрізів пам'яті (rtl-objpas/spans) з джерел гілки.
# Використання: build-spans.sh [вихідна_тека] [додаткові опції компілятора]
# Приклад перевірки витоків: build-spans.sh "" -gh
set -e
. "$(dirname "$0")/fpcenv.sh"
OUT="${1:-$ROOT/tests/concurrency/out-spans}"
[ $# -gt 0 ] && shift
mkdir -p "$OUT"
rm -f "$OUT"/*.ppu "$OUT"/*.o
# Лише spans компілюється з джерел: решта rtl-objpas береться зібраною.
"$FPC_TRUNK" @"$FPC_CFG" -gl -Sa "$@" -FU"$OUT" \
  "$ROOT/packages/rtl-objpas/src/inc/spans.pp"
"$FPC_TRUNK" @"$FPC_CFG" -gl -Sa "$@" -FU"$OUT" -FE"$OUT" -Fu"$OUT" \
  -Fu"$ROOT/packages/rtl-objpas/tests" \
  "$ROOT/tests/concurrency/test_spans.pp"
rm -f "$FPC_CFG"
echo "Готово: $OUT/test_spans"
"$OUT/test_spans" --all --format=plain
