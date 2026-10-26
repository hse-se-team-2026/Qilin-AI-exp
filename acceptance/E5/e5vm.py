#!/usr/bin/env python3
"""The VM run of E5 (E5-S5a, docs/ai/tickets/E5-S5a.md): the record docs/ucfs-integration/e5-results/vm-run.tsv
and the copy of the results that the VM run brings back (python3 standard library only).

Usage: python3 acceptance/E5/e5vm.py manifest <dir>     prints results-manifest-sha256 of <dir>
       python3 acceptance/E5/e5vm.py check <vm-run.tsv> <dir>   prints the problems (exit 1 if any)

vm-run.tsv: header "key value", the keys VMRUN_KEYS in this order:
  flavor gen-8-64, image Ubuntu-24.04, zone ru.AZ-2, disk ssd-100gb, floating-ip yes (E5.md D7);
  created (the create request of the VM was accepted), ready (SSH answers), run-started (e5-full.sh started on
  the VM), run-finished (the last part was copied back, or the run was stopped), deleted (the deletion of the VM
  with its disk and of the floating IP is confirmed): `date -Iseconds` of the machine of the executor, in this
  order; hours = (deleted - created) / 3600 with 2 decimals, at most MAX_HOURS (the stop-crane of 20 h plus an
  hour to copy and delete); rate-rub-per-hour 25.87 (E5.md D7); cost-rub = hours * rate with 2 decimals;
  parts-copied = the parts copied back, a prefix of PARTS; outcome complete (all four parts) or partial;
  stop-reason "-" when complete, else a short reason; api-after-delete "vms 0 disks 0 floating-ips 0" (the
  read of the Cloud.ru API after the deletion); results-manifest-sha256 = manifest_sha256 of the copy.
  No IP address, resource id, token or key (e5lib.secret_hits).
The copy (<dir>): setup.tsv full.log host.txt full.tsv and, for each copied part, the files of PART_FILES -
nothing else (the run directories are in <part>/raw.tar.xz); full.tsv lists exactly the copied parts.
"""
import hashlib
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e5lib  # noqa: E402

VMRUN_KEYS = ["flavor", "image", "zone", "disk", "floating-ip", "created", "ready", "run-started", "run-finished",
              "deleted", "hours", "rate-rub-per-hour", "cost-rub", "parts-copied", "outcome", "stop-reason",
              "api-after-delete", "results-manifest-sha256"]
FIXED = {"flavor": "gen-8-64", "image": "Ubuntu-24.04", "zone": "ru.AZ-2", "disk": "ssd-100gb", "floating-ip": "yes",
         "rate-rub-per-hour": "25.87", "api-after-delete": "vms 0 disks 0 floating-ips 0"}
TIMES = ["created", "ready", "run-started", "run-finished", "deleted"]
PARTS = ["bench", "minheap", "probe-cg", "probe-jdk"]
PART_FILES = {"bench": ["runs.tsv", "values.tsv", "meta.tsv", "bench.log", "raw.tar.xz"],
              "minheap": ["minheap.tsv", "steps.tsv", "meta.tsv", "minheap.log", "raw.tar.xz"],
              "probe-cg": ["runs.tsv", "values.tsv", "meta.tsv", "bench.log", "raw.tar.xz"],
              "probe-jdk": ["runs.tsv", "values.tsv", "meta.tsv", "bench.log", "raw.tar.xz"]}
TOP_FILES = ["setup.tsv", "full.log", "host.txt", "full.tsv"]
NOT_IN_MANIFEST = ["vm-run.tsv", "fallback.txt"]
MAX_HOURS = 21.0
SKEW_S = 120  # clocks of the executor and of the VM


def manifest_sha256(d):
    """sha256 of the lines "<sha256>  <path>" (paths relative to d, sorted bytewise) of every file under d
    except the top-level NOT_IN_MANIFEST files."""
    lines = []
    for dp, dn, fn in os.walk(d):
        for f in fn:
            p = os.path.join(dp, f)
            rel = os.path.relpath(p, d)
            if rel in NOT_IN_MANIFEST:
                continue
            with open(p, "rb") as fh:
                lines.append("%s  %s\n" % (hashlib.sha256(fh.read()).hexdigest(), rel))
    lines.sort(key=lambda x: x.split("  ", 1)[1].encode())
    return hashlib.sha256("".join(lines).encode()).hexdigest()


def copy_files(parts):
    return sorted(TOP_FILES + ["%s/%s" % (p, f) for p in parts for f in PART_FILES[p]])


def vmrun_problems(vmrun, d):
    """Problems of vm-run.tsv (path) against the copy d; [] = fine."""
    probs = []
    try:
        hdr = e5lib.header(vmrun)
        rows = e5lib.read_tsv(vmrun)
        text = open(vmrun, errors="replace").read()
    except OSError as e:
        return ["vm-run.tsv: %s" % e]
    if hdr != ["key", "value"] or [r["key"] for r in rows] != VMRUN_KEYS:
        probs.append("vm-run.tsv keys %s, expected %s" % ([r["key"] for r in rows], VMRUN_KEYS))
    m = {r["key"]: r["value"] for r in rows}
    probs += ["vm-run.tsv %s = %r, expected %r" % (k, m.get(k), v) for k, v in FIXED.items() if m.get(k) != v]
    t = {}
    for k in TIMES:
        v = m.get(k, "")
        if not re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d", v):
            probs.append("vm-run.tsv %s = %r is not a date -Iseconds time" % (k, v))
            continue
        t[k] = e5lib.iso_epoch(v)
    if len(t) == len(TIMES):
        if not all(t[a] < t[b] for a, b in zip(TIMES, TIMES[1:])):
            probs.append("vm-run.tsv times not in the order %s" % " < ".join(TIMES))
        h = (t["deleted"] - t["created"]) / 3600.0
        if not re.fullmatch(r"\d+\.\d\d", m.get("hours", "")) or abs(float(m["hours"]) - h) > 0.01:
            probs.append("vm-run.tsv hours %r, (deleted - created) / 3600 = %.2f" % (m.get("hours"), h))
        elif float(m["hours"]) > MAX_HOURS:
            probs.append("vm-run.tsv hours %s > %.0f (stop-crane 20 h + 1 h)" % (m["hours"], MAX_HOURS))
    try:
        if not re.fullmatch(r"\d+\.\d\d", m.get("cost-rub", "")) or \
                abs(float(m["cost-rub"]) - float(m["hours"]) * float(FIXED["rate-rub-per-hour"])) > 0.02:
            probs.append("vm-run.tsv cost-rub %r != hours x rate" % m.get("cost-rub"))
    except (KeyError, ValueError):
        probs.append("vm-run.tsv cost-rub / hours not numbers")
    parts = m.get("parts-copied", "").split()
    if not parts or parts != PARTS[:len(parts)]:
        probs.append("vm-run.tsv parts-copied %r is not a prefix of %s" % (m.get("parts-copied"), " ".join(PARTS)))
    complete = parts == PARTS
    if m.get("outcome") != ("complete" if complete else "partial"):
        probs.append("vm-run.tsv outcome %r with parts-copied %r" % (m.get("outcome"), m.get("parts-copied")))
    if (m.get("stop-reason") == "-") != complete or not m.get("stop-reason"):
        probs.append("vm-run.tsv stop-reason %r with outcome %r" % (m.get("stop-reason"), m.get("outcome")))
    for kind, s in e5lib.secret_hits(text):
        probs.append("vm-run.tsv holds a %s (%s...)" % (kind, s[:12]))
    # the copy
    if not os.path.isdir(d):
        return probs + ["copy %s is not a directory" % d]
    have = sorted(os.path.relpath(os.path.join(dp, f), d) for dp, dn, fn in os.walk(d) for f in fn)
    have = [x for x in have if x not in NOT_IN_MANIFEST]
    want = copy_files(parts if parts == PARTS[:len(parts)] else [])
    if have != want:
        probs.append("copy: files %s missing, %s not expected" % (sorted(set(want) - set(have))[:5],
                                                                   sorted(set(have) - set(want))[:5]))
    if m.get("results-manifest-sha256") != manifest_sha256(d):
        probs.append("results-manifest-sha256 %r != manifest of the copy %s" % (m.get("results-manifest-sha256"),
                                                                               manifest_sha256(d)))
    try:
        ft = e5lib.read_tsv(os.path.join(d, "full.tsv"))
        if [r["part"] for r in ft] != parts:
            probs.append("copy: full.tsv parts %s != parts-copied %s" % ([r["part"] for r in ft], parts))
        setup = e5lib.read_meta(os.path.join(d, "setup.tsv"))
        if len(t) == len(TIMES):
            if e5lib.iso_epoch(setup["started"]) < t["ready"] - SKEW_S:
                probs.append("setup.tsv started before vm-run ready")
            if e5lib.iso_epoch(setup["finished"]) > t["run-started"] + SKEW_S:
                probs.append("setup.tsv finished after vm-run run-started")
            if ft and e5lib.iso_epoch(ft[0]["started"]) < t["run-started"] - SKEW_S:
                probs.append("full.tsv starts before vm-run run-started")
            if ft and e5lib.iso_epoch(ft[-1]["finished"]) > t["run-finished"] + SKEW_S:
                probs.append("full.tsv ends after vm-run run-finished")
    except (OSError, KeyError, ValueError) as e:
        probs.append("copy: full.tsv/setup.tsv: %r" % e)
    for f, kind, s in e5lib.scan_paths([d]):
        probs.append("copy: %s holds a %s (%s...)" % (os.path.relpath(f.split("!")[0], d) + ("!" + f.split("!", 1)[1]
                                                     if "!" in f else ""), kind, s[:12]))
    return probs


def main(argv):
    if len(argv) == 3 and argv[1] == "manifest":
        print(manifest_sha256(argv[2]))
        return 0
    if len(argv) == 4 and argv[1] == "check":
        probs = vmrun_problems(argv[2], argv[3])
        for p in probs:
            print("PROBLEM: " + p)
        return 1 if probs else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
