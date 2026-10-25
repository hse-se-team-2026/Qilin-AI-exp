#!/usr/bin/env bash
# E5-S5a acceptance: the record of the VM run docs/ucfs-integration/e5-results/vm-run.tsv and the copy of the
# results brought back from the VM (docs/ai/tickets/E5-S5a.md). The VM itself is gone when this runs; what is
# checked is the committed record and the copy (acceptance/E5/e5vm.py, rules in its docstring).
#  1. docs/ucfs-integration/e5-results/vm-run.tsv exists, has the keys of e5vm.VMRUN_KEYS in order and the
#     values fixed in E5.md D7 (flavor gen-8-64, image Ubuntu-24.04, zone ru.AZ-2, disk ssd-100gb, floating IP,
#     25.87 rub/h); its times are date -Iseconds and in the order created < ready < run-started < run-finished <
#     deleted; hours = (deleted - created) / 3600 (<= 21: the stop-crane of 20 h + 1 h), cost-rub = hours x
#     rate; parts-copied is a prefix of "bench minheap probe-cg probe-jdk", outcome complete exactly when all
#     four were copied; api-after-delete is "vms 0 disks 0 floating-ips 0";
#  2. no secret in vm-run.tsv: no IPv4 address (except 127.x and 10.x), bearer token, Authorization header,
#     private or SSH key, credential word (keyId, secret, password, ...) or UUID (the ids of Cloud.ru resources)
#     (e5lib.secret_hits);
#  3. the copy <copy-dir> (the directory the executor copied the results into after each part; in the epic check
#     it is docs/ucfs-integration/e5-results itself) holds exactly setup.tsv full.log host.txt full.tsv and the
#     files of each copied part (e5vm.PART_FILES: TSV, log, <part>/raw.tar.xz; no run directories); full.tsv
#     lists the copied parts; the times of setup.tsv and full.tsv lie inside the times of vm-run.tsv (+- 120 s);
#     results-manifest-sha256 = e5vm.manifest_sha256(<copy-dir>) (every file except vm-run.tsv and
#     fallback.txt), so the results committed by E5-S5b are this copy byte for byte;
#  4. no secret in any file of the copy or in any member of its raw.tar.xz archives (e5lib.scan_paths);
#  5. tracked files unchanged.
# Usage: bash acceptance/E5/S5a_vmrun.sh <copy-dir>          (exit 0 = PASS; seconds)
source "$(dirname "$0")/lib.sh"
R="$ROOT/docs/ucfs-integration/e5-results"
[ $# -eq 1 ] && [ -d "$1" ] || die_env "usage: bash acceptance/E5/S5a_vmrun.sh <copy-dir> (the copy of the results of the VM run)"
COPY="$(realpath "$1")"
[ -f "$R/vm-run.tsv" ] && pass "vm-run.tsv exists" || { fail "no $R/vm-run.tsv"; finish S5a_vmrun; }
py "$ROOT/acceptance/E5/e5vm.py" check "$R/vm-run.tsv" "$COPY" > "$LOGS/S5a-check.txt" 2>&1
rc=$?
cat "$LOGS/S5a-check.txt"
[ $rc -eq 0 ] && pass "vm-run.tsv and the copy $COPY: format, times, cost, API read, manifest, no secrets" \
    || fail "vm-run.tsv / copy: $(grep -c '^PROBLEM' "$LOGS/S5a-check.txt") problems"
echo "  results-manifest-sha256 of the copy: $(py "$ROOT/acceptance/E5/e5vm.py" manifest "$COPY")"
tracked_clean S5a
finish S5a_vmrun
