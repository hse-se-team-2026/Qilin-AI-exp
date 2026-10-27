#!/usr/bin/env bash
# critic-E6 probe P2, second half: the same graphs (gen.py) through cfl-idr src/main compiled against
# UCFS-AI-dev bd1c111 (bd1c111-build/, the UCFS of Qilin and of E6), default stack vs -Xss1g/-Xss4g.
#   bash scripts/ucfs/bootstrap.sh            # .ucfs/m2 with bd1c111
#   (cd critic/E6/p2_sof_xss/bd1c111-build && bash ./gradlew -q -PucfsRepo=$PWD/../../../../.ucfs/m2 \
#        -PcflidrSrc=<cfl-idr-with-gll checkout> jar deps)
#   bash critic/E6/p2_sof_xss/run-bd1c111.sh <out-dir> [sites:fields ...]
# Heap 4g (RAM rule: <= 4 GB, no lock); 300 s per run.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; OUT="$1"; shift; mkdir -p "$OUT"
J="${JAVA_HOME:-$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2}/bin/java"
B="$HERE/bd1c111-build/build"; CP="$B/libs/critic-e6-cflidr-bd1c111.jar:$(ls "$B"/deps/*.jar | tr '\n' ':')"
unzip -p "$B/deps/solver-0.1.0-ai-SNAPSHOT.jar" META-INF/MANIFEST.MF | grep -E '^UCFS-(Commit|Dirty)'
for sf in "${@:-2650:194 19271:301}"; do
    s=${sf%%:*}; f=${sf##*:}; g="$OUT/g-$s-$f.dot"; python3 -I "$HERE/gen.py" "$s" "$f" "$g"
    for xss in default 1g; do
        opt=(); [ "$xss" != default ] && opt=(-Xss$xss)
        o="$OUT/o-$s-$f-$xss"; log="$OUT/run-$s-$f-xss-$xss.log"; rm -rf "$o"
        /usr/bin/time -f "wall=%e rss_kb=%M" timeout -k 10 300 "$J" -Xmx4g "${opt[@]}" -cp "$CP" org.cfl_idr_with_gll.Main -o "$o" "$g" parity > "$log" 2>&1
        rc=$?
        sof=$(grep -c 'StackOverflowError' "$log"); res=$(grep -h 'paths' "$o"/*.out 2>/dev/null | tr '\n' ' ')
        frame=$(grep -m1 -A3 'StackOverflowError' "$log" | grep -m1 -o 'org\.ucfs[A-Za-z.$]*' || true)
        echo "bd1c111 sites=$s fields=$f xss=$xss exit=$rc StackOverflowError-lines=$sof $(tail -1 "$log") result: ${res:-none} ${frame:+first-ucfs-frame=$frame}"
    done
done
