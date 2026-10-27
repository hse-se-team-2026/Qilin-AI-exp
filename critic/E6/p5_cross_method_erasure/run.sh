#!/usr/bin/env bash
# critic-E6 probe P5 (see gen.py). CFLIDR_JAR=<cfl-idr-with-gll-all.jar> bash run.sh <out-dir>
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; OUT="$1"
J="${JAVA_HOME:-$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2}/bin/java"
python3 -I "$HERE/gen.py" "$OUT"
for v in SPEC FIX; do
    d="$OUT/$v"
    "$J" -Xmx1g -jar "$CFLIDR_JAR" -o "$d/up" "$d/graph.dot" parity > "$d/up.log" 2>&1
    python3 -I - "$d" <<'PY'
import os, sys
d = sys.argv[1]
verts = {int(l.split("\t")[0]): l.rstrip("\n").split("\t") for l in open(os.path.join(d, "vertices.tsv"))}
t = open(os.path.join(d, "up", "graph.out")).read()
pairs = {tuple(map(int, l.split())) for l in t.splitlines() if l.startswith("\t")}
pts = sorted("%s <- %s" % (verts[b][3], verts[a][3]) for a, b in pairs
             if verts[a][1] == "START" and verts[b][1] in ("END", "F_IN"))
print("%s: R_over pts (START -> END/F_IN) = %s ; (oy, w) %s" % (os.path.basename(d), pts,
      "present" if "w <- oy" in pts else "MISSING"))
PY
done
