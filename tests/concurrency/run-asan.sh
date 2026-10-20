#!/bin/sh
# Перевірка -fsanitize=address (AddressSanitizer) на програмах з
# tests/concurrency/asan.
#
# Для кожної програми й кожного набору опцій (-O-, -O2, -O2 -Cg):
#   1. збирає її з -fsanitize=address (для EXPECT: clean — ще й еталон без
#      санітайзера) і запускає;
#   2. EXPECT: clean — звітів немає, код виходу 0, вивід такий самий, як
#      в еталона (трампліни не псують регістри, прапорці, SSE/x87);
#   3. інакше — звіт ASan/LeakSanitizer з цим текстом є і вказує на кожен
#      рядок із позначкою {ERR}; ACCESS: — тип і розмір доступу,
#      STACK: — підпрограми, що мають бути кадрами стеку, THREAD: — потік.
# Використання: run-asan.sh [тест...]   (без аргументів — усі)
set -u
. "$(dirname "$0")/fpcenv.sh"
DIR="$ROOT/tests/concurrency/asan"
OUT="${ASAN_OUT:-$ROOT/tests/concurrency/out-asan}"
mkdir -p "$OUT"
cd "$DIR"
if [ $# -gt 0 ]; then TESTS="$*"; else TESTS=$(ls *.pp); fi
pass=0; fail=0
for t in $TESTS; do
  t=${t%.pp}
  expect=$(head -1 "$t.pp" | sed -n 's/.*EXPECT: *\(.*[a-z]\).*/\1/p')
  access=$(head -6 "$t.pp" | sed -n 's/^ *ACCESS: *\(.*[0-9a-z]\).*/\1/p')
  stack=$(head -6 "$t.pp" | sed -n 's/^ *STACK: *//p')
  thread=$(head -6 "$t.pp" | sed -n 's/^ *THREAD: *//p')
  for opt in "-O-" "-O2" "-O2 -Cg"; do
    name="$t $opt"
    tag=$(echo "$opt" | tr -d ' ')
    ref="$OUT/ref$tag"; san="$OUT/san$tag"
    mkdir -p "$ref" "$san"
    if ! "$FPC_TRUNK" @"$FPC_CFG" $opt -gw -fsanitize=address -FU"$san" -FE"$san" "$t.pp" > "$san/$t.log" 2>&1; then
      echo "FAIL $name: sanitizer build: $(grep -m2 -E 'Error|Fatal' "$san/$t.log" | tr '\n' ' ')"; fail=$((fail+1)); continue; fi
    "$san/$t" > "$san/$t.out" 2> "$san/$t.err"
    rc=$?
    why=""
    if [ "$expect" = clean ]; then
      if ! "$FPC_TRUNK" @"$FPC_CFG" $opt -gw -FU"$ref" -FE"$ref" "$t.pp" > "$ref/$t.log" 2>&1; then
        echo "FAIL $name: reference build"; fail=$((fail+1)); continue; fi
      "$ref/$t" > "$ref/$t.out" 2>&1
      if grep -q "ERROR: \|WARNING: " "$san/$t.err"; then
        why="unexpected report: $(grep -m1 'ERROR: \|WARNING: ' "$san/$t.err")"
      elif [ $rc -ne 0 ]; then
        why="exit code $rc"
      elif ! cmp -s "$ref/$t.out" "$san/$t.out"; then
        why="output differs from the reference build"
      fi
    else
      if ! grep -q "ERROR: [A-Za-z]*Sanitizer: $expect" "$san/$t.err"; then
        why="no '$expect' report (exit $rc): $(grep -m1 'ERROR\|FATAL' "$san/$t.err")"
      else
        [ -n "$access" ] && ! grep -q "^$access at" "$san/$t.err" && why="no '$access' in the report"
        for line in $(grep -n '{ERR}' "$t.pp" | cut -d: -f1); do
          grep -q "$t.pp:$line" "$san/$t.err" || why="report does not point to $t.pp:$line"
        done
        for f in $stack; do
          grep -qE "#[0-9]+ 0x[0-9a-f]+ in $f " "$san/$t.err" || why="no stack frame $f in the report"
        done
        [ -n "$thread" ] && ! grep -q "thread $thread" "$san/$t.err" && why="error not reported in thread $thread"
      fi
    fi
    if [ -z "$why" ]; then
      echo "OK   $name"; pass=$((pass+1))
    else
      echo "FAIL $name: $why"; fail=$((fail+1))
    fi
  done
done
rm -f "$FPC_CFG"
echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
