#!/usr/bin/env bash
# E4 scale probe (NON-BLOCKING): one run of -pta=ucfs on a DaCapo-2006 benchmark WITH the JDK bodies
# (no -exclude; the options of artifact/run.py), with a time limit: the measurement behind E4.md D3
# ("JDK bodies are excluded in the E4 runs"). It never decides PASS/FAIL: exit 0 whether UCFS finished
# or not (2 only for a missing environment). Prints
#   PROBE bench=<b> timeout_s=<n> xmx=<x>
#   PROBE seam: the four #UCFS-seam- lines of a first, Spark-only run (-pta=insens -ucfsseam, the
#               global PAG that -pta=ucfs exports; -pta=ucfs itself prints them only after UCFS)
#   PROBE finished=<yes|no> exit=<java exit code, 124 = timeout> wall_s=<n> max_rss_mb=<n>
#   PROBE result: the #UCFS-import- lines when finished
# Usage: [PROBE_BENCH=luindex] [TIMEOUT=540] [XMX=16g] [REBUILD=1] bash acceptance/E4/probe_jdk.sh
#   The fat jar is acceptance/E4/out/qilin-fat.jar (built by the story checks); REBUILD=1 or a missing
#   jar builds it here.
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
[ -x /usr/bin/time ] || die_env "/usr/bin/time (GNU time) is needed for the memory measurement"
BM="${PROBE_BENCH:-luindex}"
TIMEOUT="${TIMEOUT:-540}"
XMX="${XMX:-16g}"
FRESH="$OUT/qilin-fat.jar"
if [ "${REBUILD:-0}" = 1 ] || [ ! -f "$FRESH" ]; then
    fresh_fatjar "$FRESH" || die_env "fat jar build failed (see $LOGS/fatjar.log)"
fi
dir="$OUT/probe-jdk-$BM"
safe_reset_dir "$dir"
echo "PROBE bench=$BM timeout_s=$TIMEOUT xmx=$XMX jar=$FRESH"
mkdir -p "$dir/spark"
# shellcheck disable=SC2046
(cd "$dir/spark" && timeout 600 "$JAVA" -Xmx"$XMX" -jar "$FRESH" $(dacapo_args "$BM") -jre="$JRE_DIR" $RUNPY_OPTS \
    -ucfsseam -pta=insens > out.txt 2>&1)
grep -E '^#UCFS-seam-' "$dir/spark/out.txt" | sed 's/^/PROBE seam: /'
start=$(date +%s)
# shellcheck disable=SC2046
(cd "$dir" && /usr/bin/time -v -o time.txt timeout "$TIMEOUT" "$JAVA" -Xmx"$XMX" -jar "$FRESH" \
    $(dacapo_args "$BM") -jre="$JRE_DIR" $RUNPY_OPTS -ucfsseam -pta=ucfs > out.txt 2>&1)
rc=$?
wall=$(( $(date +%s) - start ))
rss_kb=$(sed -n 's/^\s*Maximum resident set size (kbytes): //p' "$dir/time.txt")
finished=no
grep -q '^#UCFS-import-pairs:' "$dir/out.txt" && [ $rc -eq 0 ] && finished=yes
echo "PROBE finished=$finished exit=$rc wall_s=$wall max_rss_mb=$(( ${rss_kb:-0} / 1024 ))"
grep -E '^#UCFS-import-' "$dir/out.txt" | sed 's/^/PROBE result: /'
[ $rc -ne 0 ] && [ $rc -ne 124 ] && tail -n 5 "$dir/out.txt" | sed 's/^/PROBE tail: /'
echo "PROBE log: $dir/out.txt"
exit 0
