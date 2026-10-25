#!/usr/bin/env bash
# critic-E5 real probe: is "ok at -Xmx<m>" deterministic near the threshold (E5.md D3, RS4)?
# Runs the command line of acceptance/E5/S3_minheap.sh confirm() (fresh fat jar of HEAD) REPS times at each
# heap size of HEAPS for one (bench, run), and prints status (ok = exit 0 and answer = E4 committed,
# e5lib) and wall time. The machine is shared with other sessions (load1 and other java printed).
# Usage: BENCH_NAME=pmd RUN=insens HEAPS="96 104 ..." REPS=3 bash critic/E5/minheap_threshold.sh
set -u
cd "$(dirname "$0")/../.."
source acceptance/E5/lib.sh >/dev/null
JAR="$ROOT/critic/E5/out/qilin-fat.jar"
b="${BENCH_NAME:-pmd}"; run="${RUN:-insens}"; REPS="${REPS:-3}"; TO="${TO:-60}"
case "$run" in insens) opts="-pta=insens" ;; *) opts="-pta=ucfs -ucfsbinding=${run#ucfs-}" ;; esac
W="$ROOT/critic/E5/out/thr-$b-$run"
rm -rf "$W"; mkdir -p "$W"
printf 'bench\trun\txmx_mb\trep\texit\tstatus\twall_s\tload1\tother_java\n' > "$W/thr.tsv"
for r in $(seq 1 "$REPS"); do
  for mb in ${HEAPS}; do
    d="$W/x$mb-r$r"; mkdir -p "$d"
    l1=$(cut -d' ' -f1 /proc/loadavg); oj=$(pgrep -c -x java)
    s=$(date +%s.%N)
    # shellcheck disable=SC2086
    (cd "$d" && timeout -k 30 "$TO" "$JAVA" "-Xmx${mb}m" -XX:+ExitOnOutOfMemoryError -jar "$JAR" -jre="$JRE_DIR" \
        $RUNPY_OPTS $opts $(dacapo_args "$b") -ucfsseam "-exclude=$JDK_EXCLUDE" > out.txt 2>&1 < /dev/null)
    rc=$?
    e=$(date +%s.%N)
    rm -rf "$d/sootOutput"
    st=$(PYTHONPATH="$ROOT/acceptance/E5" python3 - "$d/out.txt" "$rc" "$b" "$run" "$E4_RESULTS" <<'PY'
import sys, e5lib
p, rc, b, run, e4dir = sys.argv[1:6]
txt = open(p, errors="replace").read()
rc = int(rc)
if rc == 0:
    ans = {k: v for k, v in e5lib.parse_out(txt) if not e5lib.is_measure(k)}
    print("ok" if ans == e5lib.e4_answer(e5lib.e4_values(e4dir), b, run) else "differs")
elif rc == 3 and "OutOfMemoryError" in txt: print("oom")
elif rc in (124, 137): print("timeout")
else: print("error")
PY
)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%.2f\t%s\t%s\n' "$b" "$run" "$mb" "$r" "$rc" "$st" "$(echo "$e - $s" | bc)" "$l1" "$oj" >> "$W/thr.tsv"
  done
done
column -t "$W/thr.tsv"
python3 - "$W/thr.tsv" <<'PY'
import csv, sys, collections
rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\t"))
by = collections.defaultdict(list)
for r in rows: by[int(r["xmx_mb"])].append(r["status"])
print("per heap:", " ".join("%d:%s" % (m, "/".join(s)) for m, s in sorted(by.items())))
mixed = [m for m, s in sorted(by.items()) if len(set(s)) > 1]
print("heap sizes with mixed outcomes over the repetitions:", mixed or "none")
PY
