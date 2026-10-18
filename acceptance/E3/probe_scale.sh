#!/usr/bin/env bash
# E3 scale probe (NON-BLOCKING, critic-E3 M5): one run of the CLI option -ucfspt (E3-S4) on one big
# program of qilin.microben (a program that reaches the JDK; default assign.CastFail), with a time
# limit, to give E4 a measurement instead of a guess. It never decides PASS/FAIL of a story: the
# exit code is 0 whether UCFS finished or not (2 only for a missing environment).
# Prints:
#   PROBE program=<main class> timeout_s=<n> xmx=<x>
#   PROBE seam: the four #UCFS-seam- lines (global PAG edge counts, printed before UCFS runs)
#   PROBE finished=<yes|no> exit=<java exit code, 124 = timeout> wall_s=<n> max_rss_mb=<n>
#   PROBE result: the five #UCFS-pt- lines when finished
# Usage: [PROGRAM=<class>] [TIMEOUT=<s>] [XMX=<size>] [REBUILD=1] bash acceptance/E3/probe_scale.sh
#   The fat jar is acceptance/E3/out/qilin-fat.jar (built by S4_cli_ucfspt.sh); REBUILD=1 or a
#   missing jar builds it here (gradle clean fatJar -x test).
source "$(dirname "$0")/lib.sh"
need_submodules
need_ucfs
[ -x /usr/bin/time ] || die_env "/usr/bin/time (GNU time) is needed for the memory measurement"

PROGRAM="${PROGRAM:-qilin.microben.core.assign.CastFail}"
TIMEOUT="${TIMEOUT:-540}"
XMX="${XMX:-16g}"
FRESH="$OUT/qilin-fat.jar"
if [ "${REBUILD:-0}" = 1 ] || [ ! -f "$FRESH" ]; then
    build_fatjar "$FRESH" clean fatJar -x test || die_env "fat jar build failed (see $LOGS/fatjar.log)"
fi

dir="$OUT/probe-scale"
safe_reset_dir "$dir"
echo "PROBE program=$PROGRAM timeout_s=$TIMEOUT xmx=$XMX jar=$FRESH"
start=$(date +%s)
(cd "$dir" && /usr/bin/time -v -o time.txt timeout "$TIMEOUT" "$JAVA" -Xmx"$XMX" -jar "$FRESH" \
    -apppath "$MICROBEN_CLASSES" -mainclass "$PROGRAM" -jre="$JRE_DIR" \
    -pta=insens -se -ucfsseam -ucfspt > out.txt 2>&1)
rc=$?
wall=$(( $(date +%s) - start ))
rss_kb=$(sed -n 's/^\s*Maximum resident set size (kbytes): //p' "$dir/time.txt")
grep -E '^#UCFS-seam-' "$dir/out.txt" | sed 's/^/PROBE seam: /'
finished=no
grep -q '^#UCFS-pt-pairs:' "$dir/out.txt" && [ $rc -eq 0 ] && finished=yes
echo "PROBE finished=$finished exit=$rc wall_s=$wall max_rss_mb=$(( ${rss_kb:-0} / 1024 ))"
grep -E '^#UCFS-pt-' "$dir/out.txt" | sed 's/^/PROBE result: /'
[ $rc -ne 0 ] && [ $rc -ne 124 ] && tail -n 5 "$dir/out.txt" | sed 's/^/PROBE tail: /'
echo "PROBE log: $dir/out.txt"
exit 0
