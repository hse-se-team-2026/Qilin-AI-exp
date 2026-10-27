#!/usr/bin/env python3
"""Checker of docs/ucfs-integration/cflidr-export.md (E6-S7, docs/ai/tickets/E6-S7.md).

Usage: python3 acceptance/E6/doc_check.py <doc.md> <e6-results-dir>      (exit 0 = all checks pass)

Built on acceptance/E3/doc_check.py (pinned code references) and acceptance/E5/doc_check.py (numbers
bound to a benchmark). Prose = lines outside ``` fences that are not headings or table rows; sentences
split at . ! ? ; followed by a blank; code spans are not prose.
  * pins (first 15 lines): `pin: <40-hex>` - a Qilin-AI-exp commit, ancestor of HEAD, that has
    qilin.ucfs/src/main/kotlin/qilin/ucfs/idr/; `cflidr-pin: <40-hex>` = cflidrCommit of
    scripts/cflidr/cflidr.properties. References: `<path>:<line>#<symbol>` or `<path>:<a>-<b>#<symbol>`
    (Qilin, at pin) and `cflidr:<path>:...#<symbol>` (cfl-idr-with-gll in .cflidr/src, at cflidr-pin);
    the file exists there, the range has <= 61 lines and holds <symbol> as a word in code (not only in
    a comment). Links do not follow the working tree, so later line shifts do not break them (E9 #43);
    a `<file>.(kt|java|kts|gradle|py|sh):<n>` without `#<symbol>` fails;
  * the headings HEADINGS in this order, the words of MENTIONS inside their sections;
  * table T1 of `python3 acceptance/E6/e6tables.py <results>` occurs verbatim in section 5; every run of
    runs.tsv whose status is not ok is named in a sentence of section 5 with its benchmark, mode, status and
    (unless "-") its last_phase (r2: where the run stood, critic MAJOR-5);
  * (r2, critic MAJOR-5) if no CS run of runs.tsv is ok, a sentence of section 7 names "CS" and "microben"
    (what E7 can import with CS) and a sentence of section 6 or 7 says "CS" with "DaCapo" and "не получен";
  * bibliography: tokens shaped like a bib key are keys of acceptance/E3/bib_keys.txt; REQUIRED_KEYS cited;
  * "проверено:" counts only with a reference, a `command` starting with "bash acceptance/",
    "python3 acceptance/", "bash scripts/" or "java acceptance/" whose script exists, or a path into
    docs/ucfs-integration/e6-results/;
  * claim sweep: a sentence with a word of UNIVERSAL or CAUSAL carries a reference, a bib key,
    "интерпретация" or "проверено:" with a source;
  * numbers: every number of a prose sentence (outside code, references, bib keys) is in WHITELIST, or
    the sentence is "проверено:" with a source (printed as NUMBER: for the verifier), or it is a cell of
    T1 in a row of the benchmark named closest before it in the sentence (closest after if none
    before); with no benchmark named, any cell of T1;
  * the word "интерпретация" occurs at least once.
Prints JUDGE: per reference, CLAIM: per marked sentence, NUMBER: per number taken from a "проверено:"
sentence; the verifier judges all of them.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CFLIDR_SRC = os.path.join(ROOT, ".cflidr", "src")
HEADINGS = [
    ("## 1.", "cfl-idr"),
    ("## 2.", "Кодирование"),
    ("## 3.", "Подключение"),
    ("## 4.", "Корректность"),
    ("## 5.", "DaCapo"),
    ("## 6.", "Ограничения"),
    ("## 7.", "Следствие"),
]
MENTIONS = {
    1: ["R_under", "R_over", "getUnderApprox", "getMROverApprox", "getOnDemandMR", "op--", "ob--", "normal"],
    2: ["START", "END", "F_IN", "ERASED", "BALANCED", "CS", "частичн", "стира", "cb--", "Sridharan2006Refinement"],
    3: ["solver-new.jar", "PR #50", "bd1c111", "ucfs-main", "scripts/cflidr/bootstrap.sh", "cflidrCommit",
        "TestExtractEdgesFromSppfResult"],
    4: ["E6IdrFieldsTest", "E6IdrCsTest", "CsModel", "mayAlias", "notAlias", "Andersen", "CsFacts", "solver-new.jar",
        "sparkWithinFieldsExport", "csErasureAtCrossMethodNew", "boundedTruncatedObjects", "Spark"],
    5: ["e6-probe.sh", "IdrDyckCheck", "-cflidrstack", "evidence.tsv", "raw.tar.xz", "Spark"],
    6: ["Reps2000Undecidability", "R1", "R3", "интерпретация"],
    7: ["E7", "E8"],
}
REQUIRED_KEYS = ["Conrado2025Cfl", "Ding2023Mutual", "Reps2000Undecidability", "Sridharan2006Refinement",
                 "Sridharan2005Demand"]
UNIVERSAL = ["только", "никогда", "всегда", "все ", "всех", "любой", "любая", "любое", "каждый", "каждая", "каждое",
             "гарантир", "точно", "ровно", "полностью", "невозможно", "only", "never", "always", "every", "exactly",
             "guarantee"]
CAUSAL = ["потому что", "поэтому", "из-за", "так как", "следовательно", "значит", "because", "therefore"]
WHITELIST = set(str(i) for i in range(0, 11)) | {"21", "2026", "2025", "2006", "2005", "2000", "50", "61", "43", "18"}
BENCHES = ["antlr", "bloat", "chart", "eclipse", "fop", "luindex", "lusearch", "pmd", "xalan", "checkstyle", "findbugs", "JPC"]
REF = re.compile(r"(?:(cflidr):)?([\w./-]+\.(?:kt|java|kts|gradle|py|sh)):(\d+)(?:-(\d+))?#(\w+)")
BARE = re.compile(r"[\w./-]+\.(?:kt|java|kts|gradle|py|sh):\d+(?![\d-]*#)")
KEY = re.compile(r"\b[A-Z][a-z]+(?:[A-Z][a-z]+)*\d{4}[A-Z][a-z]+\b")
NUM = re.compile(r"(?<![\w.])\d+(?:[.,]\d+)?(?![\w])")
fails = []


def fail(msg):
    fails.append(msg)
    print("FAIL: " + msg)


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True)
    return r.returncode, r.stdout


def main():
    doc, res = sys.argv[1], sys.argv[2]
    text = open(doc, encoding="utf-8").read()
    lines = text.split("\n")
    head = "\n".join(lines[:15])
    pin = re.search(r"^pin: ([0-9a-f]{40})\s*$", head, re.M)
    cpin = re.search(r"^cflidr-pin: ([0-9a-f]{40})\s*$", head, re.M)
    props = open(os.path.join(ROOT, "scripts", "cflidr", "cflidr.properties")).read()
    ccommit = re.search(r"^cflidrCommit=([0-9a-f]{40})", props, re.M)
    if not pin:
        fail("no line 'pin: <40-hex>' in the first 15 lines")
    else:
        pin = pin.group(1)
        if git(ROOT, "merge-base", "--is-ancestor", pin, "HEAD")[0] != 0:
            fail("pin %s is not an ancestor of HEAD" % pin)
        if git(ROOT, "cat-file", "-e", pin + ":qilin.ucfs/src/main/kotlin/qilin/ucfs/idr")[0] != 0:
            fail("pin %s has no qilin.ucfs/src/main/kotlin/qilin/ucfs/idr" % pin)
    if not cpin or not ccommit or cpin.group(1) != ccommit.group(1):
        fail("cflidr-pin missing or != cflidrCommit of scripts/cflidr/cflidr.properties")
    cpin = cpin.group(1) if cpin else None

    # sections
    sec_of_line, cur, pos = [], 0, 0
    for l in lines:
        for i, (pre, word) in enumerate(HEADINGS, 1):
            if l.startswith(pre) and word in l:
                if i != cur + 1:
                    fail("heading %r out of order" % l)
                cur = i
        sec_of_line.append(cur)
    if cur != len(HEADINGS):
        fail("headings: found %d of %d (%s)" % (cur, len(HEADINGS), [h for h, _ in HEADINGS]))
    sections = {i: "\n".join(l for l, s in zip(lines, sec_of_line) if s == i) for i in range(1, 8)}
    for s, words in MENTIONS.items():
        for w in words:
            if w not in sections.get(s, ""):
                fail("section %d does not mention %r" % (s, w))

    # references
    for m in REF.finditer(text):
        repo, path, a, b, sym = m.group(1), m.group(2), int(m.group(3)), int(m.group(4) or m.group(3)), m.group(5)
        where, commit = (CFLIDR_SRC, cpin) if repo else (ROOT, pin)
        if not commit or b < a or b - a > 60:
            fail("reference %s: no pin or bad range" % m.group(0))
            continue
        rc, out = git(where, "show", "%s:%s" % (commit, path))
        if rc != 0:
            fail("reference %s: no %s at %s" % (m.group(0), path, commit[:7]))
            continue
        src = out.split("\n")[a - 1:b]
        code = [re.sub(r"//.*$|^\s*\*.*$|/\*.*?\*/|#.*$" if path.endswith((".py", ".sh", ".gradle")) else r"//.*$|^\s*\*.*$|/\*.*?\*/", "", l) for l in src]
        if len(src) < b - a + 1 or not any(re.search(r"\b%s\b" % re.escape(sym), c) for c in code):
            fail("reference %s: %s not in code on those lines" % (m.group(0), sym))
        else:
            print("JUDGE: %s" % m.group(0))
    for m in BARE.finditer(re.sub(REF, "", text)):
        fail("reference without #symbol: %s" % m.group(0))

    # bibliography
    keys = set(open(os.path.join(ROOT, "acceptance", "E3", "bib_keys.txt")).read().split())
    cited = set(KEY.findall(text))
    for k in sorted(cited - keys):
        fail("bib key %s not in references.bib" % k)
    for k in REQUIRED_KEYS:
        if k not in cited:
            fail("required bib key %s not cited" % k)

    # table T1
    t1 = subprocess.run([sys.executable, os.path.join(ROOT, "acceptance", "E6", "e6tables.py"), res],
                        capture_output=True, text=True)
    if t1.returncode != 0 or t1.stdout.strip() not in sections.get(5, ""):
        fail("table T1 of e6tables.py is not verbatim in section 5")
    rows = [[c.strip() for c in l.strip("|").split("|")] for l in t1.stdout.strip().split("\n")[2:]]
    runs = [l.split("\t") for l in open(os.path.join(res, "runs.tsv")).read().strip().split("\n")[1:]]

    # prose sentences
    prose, infence = [], False
    for l, s in zip(lines, sec_of_line):
        if l.startswith("```"):
            infence = not infence
            continue
        if infence or l.startswith("#") or l.startswith("|") or not l.strip():
            continue
        prose.append((l, s))
    sentences = []
    for l, s in prose:
        for sent in re.split(r"(?<=[.!?;])\s+", l):
            sentences.append((sent, s))
    for r in runs:
        bench, mode, grammar, status, last = r[0], r[1], r[2], r[4], r[8]
        if status != "ok" and not any(bench in t and mode in t and status in t and (last == "-" or last in t)
                                      for t, s in sentences if s == 5):
            fail("section 5 does not name %s %s %s with status %s and last phase %s" % (bench, mode, grammar, status, last))
    if not any(r[1] == "CS" and r[4] == "ok" for r in runs):
        if not any("CS" in t and "microben" in t for t, s in sentences if s == 7):
            fail("no CS run is ok: section 7 has no sentence with 'CS' and 'microben'")
        if not any("CS" in t and "DaCapo" in t and "не получен" in t for t, s in sentences if s in (6, 7)):
            fail("no CS run is ok: sections 6-7 have no sentence with 'CS', 'DaCapo' and 'не получен'")
    if "интерпретация" not in text:
        fail("the word 'интерпретация' does not occur")
    for sent, s in sentences:
        bare = re.sub(r"`[^`]*`", "", sent)
        has_ref = bool(REF.search(sent))
        has_key = bool(KEY.search(sent))
        checked = re.search(r"проверено:", sent)
        source = None
        if checked:
            cmds = re.findall(r"`((?:bash|python3|java) (?:acceptance|scripts)/[^`]+)`", sent)
            ok_cmd = any(os.path.isfile(os.path.join(ROOT, c.split()[1])) for c in cmds)
            source = has_ref or ok_cmd or "docs/ucfs-integration/e6-results/" in sent
            if not source:
                fail("'проверено:' without a source: %s" % sent.strip()[:160])
        elif "проверено" in sent:
            fail("bare 'проверено' (use 'проверено:' with a source): %s" % sent.strip()[:160])
        low = " " + bare.lower() + " "
        claim = any(w in low for w in UNIVERSAL) or any(w in low for w in CAUSAL)
        if claim and not (has_ref or has_key or "интерпретация" in low or source):
            fail("claim without reference, bib key, 'интерпретация' or 'проверено:': %s" % sent.strip()[:160])
        if claim or checked or "интерпретация" in low:
            print("CLAIM: [%d] %s" % (s, sent.strip()[:300]))
        stripped = REF.sub("", KEY.sub("", bare))
        stripped = re.sub(r"\b[DEMRS]\d+\b|\bE\d+-S\d+\w*|#\d+|§\s*\d+(?:\.\d+)*", "", stripped)
        for m in NUM.finditer(stripped):
            n = m.group(0).replace(",", ".")
            if n in WHITELIST:
                continue
            if source:
                print("NUMBER: %s | %s" % (n, sent.strip()[:200]))
                continue
            before = [b for b in BENCHES if re.search(r"\b%s\b" % b, stripped[:m.start()])]
            after = [b for b in BENCHES if re.search(r"\b%s\b" % b, stripped[m.end():])]
            bench = (sorted(before, key=lambda b: stripped[:m.start()].rfind(b))[-1:] or
                     sorted(after, key=lambda b: stripped[m.end():].find(b))[:1])
            cells = [c for row in rows if not bench or row[0] == bench[0] for c in row[1:]]
            if n not in cells and n.rstrip("0").rstrip(".") not in cells:
                fail("number %s not in T1 (%s) and no 'проверено:' with a source: %s"
                     % (n, bench[0] if bench else "any row", sent.strip()[:160]))
    print("doc_check: %d failure(s)" % len(fails))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
