#!/usr/bin/env bash
# critic-E6 probe P2 (see gen.py): cfl-idr CLI (root build, solver-new.jar) with the default thread stack
# and with -Xss1g, on graphs with the id counts of luindex (2650 sites, 194 fields) and antlr (19271, 301).
#   CFLIDR_JAR=<cfl-idr-with-gll-all.jar> bash critic/E6/p2_sof_xss/run.sh <out-dir>
# Heap 4g (RAM rule: <= 4 GB, no lock needed); 300 s per run.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; OUT="$1"; mkdir -p "$OUT"
J="${JAVA_HOME:-$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2}/bin/java"
for sf in "2650 194" "19271 301"; do
    set -- $sf; g="$OUT/g-$1-$2.dot"; python3 -I "$HERE/gen.py" "$1" "$2" "$g"
    for xss in default 1g; do
        opt=(); [ "$xss" != default ] && opt=(-Xss$xss)
        log="$OUT/run-$1-$2-xss-$xss.log"; rm -rf "$OUT/o-$1-$2-$xss"
        /usr/bin/time -f "wall=%e rss_kb=%M" timeout -k 10 300 "$J" -Xmx4g "${opt[@]}" -jar "$CFLIDR_JAR" -o "$OUT/o-$1-$2-$xss" "$g" parity > "$log" 2>&1
        rc=$?
        sof=$(grep -c 'StackOverflowError' "$log"); res=$(grep -h 'paths' "$OUT/o-$1-$2-$xss/"*.out 2>/dev/null | tr '\n' ' ')
        frame=$(grep -m1 -A3 'StackOverflowError' "$log" | grep -m1 -o 'org\.ucfs[A-Za-z.$]*' || true)
        echo "sites=$1 fields=$2 xss=$xss exit=$rc StackOverflowError-lines=$sof $(tail -1 "$log") result: ${res:-none} ${frame:+first-ucfs-frame=$frame}"
    done
done
