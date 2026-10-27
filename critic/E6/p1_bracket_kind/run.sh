#!/usr/bin/env bash
# critic-E6 probe P1 (see gen.py). Needs the cfl-idr CLI jar of the root build (solver-new.jar):
#   CFLIDR_JAR=<cfl-idr-with-gll-all.jar> bash critic/E6/p1_bracket_kind/run.sh <out-dir>
# For each encoding: cfl-idr CLI (parity) -> pts (OBJ -> F) ; compare with Andersen; then run the S6
# oracle acceptance/E6/IdrDyckCheck.java with pts files = cfl-idr's answer (what -cflidr would dump).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../../.." && pwd)"
OUT="$1"; J="${JAVA_HOME:-$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2}/bin/java"
python3 -I "$HERE/gen.py" "$OUT"
for m in D4 M1; do
    d="$OUT/$m"
    "$J" -Xmx1g -jar "$CFLIDR_JAR" -o "$d/up" "$d/graph.dot" parity > "$d/up.log" 2>&1
    python3 -I - "$d" <<'PY'
import sys, os
d = sys.argv[1]
verts = {int(l.split("\t")[0]): l.rstrip("\n").split("\t") for l in open(os.path.join(d, "vertices.tsv"))}
t = open(os.path.join(d, "up", "graph.out")).read()
under_n = int(t.split("Under approximation paths: ")[1].split()[0])
pairs = {tuple(map(int, l.split())) for l in t.splitlines() if l.startswith("\t")}
pts = sorted("%s\t%s" % (verts[b][3], verts[a][3]) for a, b in pairs if verts[a][1] == "OBJ" and verts[b][1] == "F")
open(os.path.join(d, "pts-over.tsv"), "w").write("".join(p + "\n" for p in pts))
open(os.path.join(d, "pts-under.tsv"), "w").write("".join(p + "\n" for p in pts))  # ERASED: under = over
ref = {l.rstrip("\n") for l in open(os.path.join(os.path.dirname(d), "andersen.tsv"))}
extra, missing = sorted(set(pts) - ref), sorted(ref - set(pts))
print("%s: cfl-idr under=%d over=%d pt=%d ; vs Andersen: extra=%s missing=%s" % (os.path.basename(d), under_n, len(pairs), len(pts), extra, missing))
PY
    echo "$m: IdrDyckCheck on the dump (pts = cfl-idr's answer):"
    "$J" -Xmx1g "$ROOT/acceptance/E6/IdrDyckCheck.java" "$d" | sed 's/^/    /'; echo "    exit ${PIPESTATUS[0]}"
done
