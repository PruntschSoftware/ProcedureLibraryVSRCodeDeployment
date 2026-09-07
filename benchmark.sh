#!/usr/bin/env bash
#
# benchmark.sh
#
# 1. kompiliert die Testprozeduren src/procedures/test*.p nach build/rcode
# 2. ruft alle Prozeduren dynamisch genau einmal auf (lose r-Files im PROPATH)
#    und misst die dafuer benoetigte Zeit
# 3. packt dieselben r-Files in eine Procedure Library build/lib/testlib.pl
# 4. wiederholt die Messung mit der Library im PROPATH
# 5. gibt den Unterschied der beiden Messungen aus
#
# Voraussetzung: installierte OpenEdge Runtime, $DLC gesetzt (oder /usr/dlc).
# Anzahl der Prozeduren ueber COUNT steuerbar, z.B.: COUNT=1000 ./benchmark.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

export DLC="${DLC:-/usr/dlc}"
PROGRES="$DLC/bin/_progres"
PROLIB="$DLC/bin/prolib"
COUNT="${COUNT:-1000}"

SRC_DIR="src/procedures"
BUILD_DIR="build"
RCODE_DIR="$BUILD_DIR/rcode"
LIB_DIR="$BUILD_DIR/lib"
LIB="$LIB_DIR/testlib.pl"
RESULT="$BUILD_DIR/results.csv"

if [ ! -x "$PROGRES" ]; then
    echo "OpenEdge Runtime nicht gefunden: $PROGRES (DLC setzen)" >&2
    exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$RCODE_DIR" "$LIB_DIR"

echo "== Kompiliere $SRC_DIR nach $RCODE_DIR =="
"$PROGRES" -b -p src/build/compile-tests.p -param "$SRC_DIR,$RCODE_DIR"

echo "== Messung 1: lose r-Files =="
PROPATH="$ROOT/$RCODE_DIR" "$PROGRES" -b -p src/build/runtests.p \
    -param "r-Files,$COUNT,$RESULT"

echo "== Erstelle Procedure Library $LIB =="
"$PROLIB" "$ROOT/$LIB" -create
( cd "$RCODE_DIR" && ls *.r | xargs -n 100 "$PROLIB" "$ROOT/$LIB" -add >/dev/null )
"$PROLIB" "$ROOT/$LIB" -list | tail -n 1

echo "== Messung 2: Procedure Library =="
PROPATH="$ROOT/$LIB" "$PROGRES" -b -p src/build/runtests.p \
    -param "Procedure Library,$COUNT,$RESULT"

echo
echo "== Ergebnis =="
awk -F';' '
    { ms[NR] = $3
      printf "%-20s %6d Prozeduren %8d ms\n", $1, $2, $3 }
    END {
      if (NR >= 2 && ms[1] > 0)
          printf "Unterschied: %d ms (%.1f %%)\n", ms[1] - ms[2],
                 (ms[1] - ms[2]) * 100 / ms[1]
    }' "$RESULT"
