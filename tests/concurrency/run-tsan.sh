#!/bin/sh
# Перевірка -fsanitize=thread (ThreadSanitizer) на програмах з tests/concurrency/tsan.
#
# Для кожної програми й кожного набору опцій (-O-, -O2, -O2 -Cg):
#   1. збирає її без санітайзера (еталон) і з -fsanitize=thread;
#   2. запускає інструментовану під setarch -R (TSan з GCC 13 несумісний
#      з високою ентропією ASLR сучасних ядер Linux);
#   3. перевіряє, що вивід програми такий самий, як в еталона;
#   4. перевіряє очікування з першого рядка (EXPECT: race | norace): для race —
#      що звіт TSan є і вказує на кожен рядок із позначкою {RACE}, для
#      norace — що звітів немає.
# Використання: run-tsan.sh [тест...]   (без аргументів — усі)
set -u
. "$(dirname "$0")/fpcenv.sh"
DIR="$ROOT/tests/concurrency/tsan"
OUT="${TSAN_OUT:-$ROOT/tests/concurrency/out-tsan}"
mkdir -p "$OUT"
cd "$DIR"
if [ $# -gt 0 ]; then TESTS="$*"; else TESTS=$(ls *.pp | grep -v '^tsanutil'); fi
pass=0; fail=0
for t in $TESTS; do
  t=${t%.pp}
  expect=$(head -1 "$t.pp" | sed -n 's/.*EXPECT: *\([a-z]*\).*/\1/p')
  for opt in "-O-" "-O2" "-O2 -Cg"; do
    name="$t $opt"
    tag=$(echo "$opt" | tr -d ' ')
    ref="$OUT/ref$tag"; san="$OUT/san$tag"
    mkdir -p "$ref" "$san"
    if ! "$FPC_TRUNK" @"$FPC_CFG" $opt -gw -FU"$ref" -FE"$ref" "$t.pp" > "$ref/$t.log" 2>&1; then
      echo "FAIL $name: reference build"; fail=$((fail+1)); continue; fi
    if ! "$FPC_TRUNK" @"$FPC_CFG" $opt -gw -fsanitize=thread -FU"$san" -FE"$san" "$t.pp" > "$san/$t.log" 2>&1; then
      echo "FAIL $name: sanitizer build: $(grep -m2 -E 'Error|Fatal' "$san/$t.log" | tr '\n' ' ')"; fail=$((fail+1)); continue; fi
    "$ref/$t" > "$ref/$t.out" 2>&1
    TSAN_OPTIONS="exitcode=66 halt_on_error=0 history_size=4" \
      setarch "$(uname -m)" -R "$san/$t" > "$san/$t.out" 2> "$san/$t.err"
    rc=$?
    why=""
    # the program output (stdout) must not change
    if ! cmp -s "$ref/$t.out" "$san/$t.out"; then
      why="output differs from the reference build"
    elif grep -q "FATAL\|DEADLYSIGNAL" "$san/$t.err"; then
      why="sanitizer failure: $(grep -m1 'FATAL\|ERROR' "$san/$t.err")"
    elif [ "$expect" = race ]; then
      if ! grep -q "WARNING: ThreadSanitizer: data race" "$san/$t.err"; then
        why="no data race reported (exit $rc)"
      else
        for line in $(grep -n '{RACE}' "$t.pp" | cut -d: -f1); do
          grep -q "$t.pp:$line" "$san/$t.err" || why="race report does not point to $t.pp:$line"
        done
      fi
    else
      if grep -q "WARNING: ThreadSanitizer" "$san/$t.err"; then
        why="unexpected report: $(grep -m1 'WARNING: ThreadSanitizer' "$san/$t.err")"
      elif [ $rc -ne 0 ]; then
        why="exit code $rc"
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
