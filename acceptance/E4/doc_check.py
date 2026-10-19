#!/usr/bin/env python3
"""Checker of docs/ucfs-integration/ucfs-vs-spark.md against the committed results (E4-S6,
docs/ai/tickets/E4-S6.md).

Usage: python3 acceptance/E4/doc_check.py <doc.md> <results-dir>     (exit 0 = all checks pass)
<results-dir> holds runs.tsv, values.tsv and examples.tsv written by scripts/ucfs/e4-bench.sh.

Checks:
  * results: runs.tsv covers exactly the 12 benchmarks of E4.md D3 (BENCHES) with the runs insens,
    ucfs-ANALYSIS, ucfs-CALL_GRAPH each; ucfs-ANALYSIS finished (status ok) on >= 2 benchmarks; in every
    finished ucfs run the call-graph metrics are equal in the three views; a finished ucfs run with
    UCFS-cmp-MISSING or UCFS-cmp-UNEXPLAINED > 0 needs a prose line of the document naming the
    benchmark and that class;
  * the section headings HEADINGS, in this order;
  * the four tables of acceptance/E4/tables.py on <results-dir> occur verbatim in the document;
  * examples: every line "EXAMPLE <bench> <run> <class>: `<var>` <- `<object>` - <explanation>" is a row
    of examples.tsv and its explanation (outside code spans) has >= 12 words; every class among R1 R2
    R3 R4b R5 with a non-zero count in some finished run has >= 1 example, R1 and R3 (when non-zero)
    from >= 2 different benchmarks if examples.tsv has them for >= 2;
  * dispatch: every finished run with UCFS-cmp-dispatch-new-edges-UCFS > 0 has a line
    "DISPATCH <bench> <binding>: ..." with >= 12 words outside code spans;
  * code references `<repo path>:<line>#<symbol>` or `<repo path>:<from>-<to>#<symbol>` (range of at most
    61 lines) resolve in the working tree: the file exists and <symbol> occurs on those lines as a word;
  * bibliography: every token shaped like a bib key (AuthorYYYYWord) is a key of acceptance/E3/bib_keys.txt,
    and REQUIRED_KEYS are cited;
  * mandatory mentions (MENTIONS);
  * claim sweep: every prose sentence with a universal or absolute word (UNIVERSAL) also carries a code
    reference, a bib key, or the mark "интерпретация", or "проверено:" followed by a code reference or a
    `command` in backticks; the word "интерпретация" occurs at least once.
Prints one "JUDGE:" line per example, dispatch line and code reference, and one "CLAIM:" line per marked
sentence: the verifier judges every one of them against the code (E3 lesson: the mechanics check the
marks, not the truth).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tables  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BENCHES = ["antlr", "bloat", "chart", "eclipse", "fop", "luindex", "lusearch", "pmd", "xalan", "checkstyle",
           "findbugs", "JPC"]
RUNS = ["insens", "ucfs-ANALYSIS", "ucfs-CALL_GRAPH"]
HEADINGS = [
    "## 1. Постановка и конфигурация",
    "## 2. Импорт ответа UCFS в Qilin",
    "## 3. Результаты",
    "## 4. Классы расхождений и примеры",
    "## 5. Граф вызовов",
    "## 6. Масштаб и ограничения",
    "## 7. Воспроизведение",
]
REQUIRED_KEYS = ["Sridharan2005Demand", "He2022Qilin", "Lhotak2003Scaling"]
MENTIONS = ["по построению", "ROOT", "R1", "R2", "R3", "R4b", "R5", "UNEXPLAINED", "MISSING", "UCFS_TYPED",
            "-exclude", "probe_jdk.sh", "RS7", "-pta=ucfs", "-ucfscompare", "e4-bench.sh", "CALL_GRAPH",
            "ANALYSIS"]
UNIVERSAL = ["только", "никогда", "всегда", "все", "всех", "всем", "всё", "любой", "любая", "любое", "каждый",
             "каждая", "каждое", "каждого", "каждой", "всего", "гарантирует", "гарантированно", "точно", "ровно",
             "полностью", "никакой", "ни один", "ни одна", "ни одного", "only", "never", "always", "all", "any",
             "every", "each", "none", "exactly", "guarantee", "guarantees", "completely"]
BIB = re.compile(r"\b([A-Z][A-Za-z]+(?:19|20)\d\d[A-Z][A-Za-z]*)\b")
REF = re.compile(r"`?([\w./-]+\.(?:java|kt|sh|py|gradle)):(\d+)(?:-(\d+))?#([\w$<>]+)`?")
fails = []


def ok(m):
    print("PASS: " + m)


def ko(m):
    print("FAIL: " + m)
    fails.append(m)


def tsv(p):
    return [l.rstrip("\n").split("\t") for l in open(p) if l.strip()]


def prose_words(s):
    return len(re.findall(r"[\wА-Яа-яЁё]{2,}", re.sub(r"`[^`]*`", " ", s)))


def main():
    doc_path, res = sys.argv[1], sys.argv[2]
    text = open(doc_path, encoding="utf-8").read()
    lines = text.split("\n")
    prose = []
    fenced = False
    for i, l in enumerate(lines):
        if l.strip().startswith("```"):
            fenced = not fenced
            continue
        if not fenced:
            prose.append((i + 1, l))

    # --- results
    runs = {(r[0], r[1]): r for r in tsv(os.path.join(res, "runs.tsv"))[1:]}
    vals = {(r[0], r[1], r[2]): r[3] for r in tsv(os.path.join(res, "values.tsv"))[1:]}
    exrows = {tuple(r) for r in tsv(os.path.join(res, "examples.tsv"))[1:]}
    if sorted(runs) == sorted((b, r) for b in BENCHES for r in RUNS):
        ok("runs.tsv: the 12 benchmarks x insens, ucfs-ANALYSIS, ucfs-CALL_GRAPH")
    else:
        ko("runs.tsv covers %s" % sorted(runs))
    okA = [b for b in BENCHES if runs.get((b, "ucfs-ANALYSIS"), [""] * 3)[2] == "ok"]
    (ok if len(okA) >= 2 else ko)("ucfs-ANALYSIS finished on %d benchmarks: %s" % (len(okA), okA))
    finished = [(b, r) for (b, r), f in runs.items() if r != "insens" and f[2] == "ok"]
    for b, r in sorted(finished):
        for m in ["Reachable Method (CI)", "Call Edge(CI)", "Virtual Call Site(Polymorphic)"]:
            xs = {vals.get((b, r, "cmp/%s/%s" % (v, m))) for v in ["SPARK", "UCFS", "UCFS_TYPED"]}
            if len(xs) != 1 or None in xs:
                ko("%s/%s %s differs between views: %s" % (b, r, m, xs))
        for c in ["MISSING", "UNEXPLAINED"]:
            n = vals.get((b, r, "UCFS-cmp-" + c))
            if n != "0":
                hit = [ln for ln, l in prose if b in l and c in l and not l.startswith("|")]
                (ok if hit else ko)("%s/%s %s=%s %s" % (b, r, c, n, "explained at line %d" % hit[0] if hit else "not explained in prose"))

    # --- headings
    heads = [l for _, l in prose if l.startswith("## ")]
    pos = [heads.index(h) if h in heads else -1 for h in HEADINGS]
    if -1 not in pos and pos == sorted(pos):
        ok("the %d section headings in order" % len(HEADINGS))
    else:
        ko("headings missing %s or out of order %s" % ([h for h, p in zip(HEADINGS, pos) if p == -1], pos))

    # --- tables
    for n, t in tables.render(res).items():
        (ok if t in text else ko)("table %s of tables.py %s the document" % (n, "is in" if t in text else "is not verbatim in"))

    # --- examples
    exre = re.compile(r"^EXAMPLE (\S+) (\S+) (\S+): `([^`]*)` <- `([^`]*)` [-—] (.*)$")
    seen = {}
    for ln, l in prose:
        if l.startswith("EXAMPLE"):
            m = exre.match(l)
            if not m:
                ko("line %d: EXAMPLE line not in the form EXAMPLE <bench> <run> <class>: `var` <- `object` - text" % ln)
                continue
            b, r, c, v, o, expl = m.groups()
            if (b, r, c, v, o) not in exrows:
                ko("line %d: EXAMPLE is not a row of examples.tsv: %s %s %s" % (ln, b, r, c))
                continue
            if prose_words(expl) < 12:
                ko("line %d: EXAMPLE explanation has %d words (< 12)" % (ln, prose_words(expl)))
                continue
            seen.setdefault(c, set()).add(b)
            print("JUDGE: example line %d: %s %s %s" % (ln, b, r, c))
    for c in ["R1", "R2", "R3", "R4b", "R5"]:
        nz = [b for (b, r) in finished if vals.get((b, r, "UCFS-cmp-" + c), "0") not in ("0", None)]
        if not nz:
            continue
        need = 2 if c in ("R1", "R3") and len({row[0] for row in exrows if row[2] == c}) >= 2 else 1
        got = len(seen.get(c, set()))
        (ok if got >= need else ko)("class %s (non-zero in %d runs): examples from %d benchmark(s), need %d" % (c, len(nz), got, need))

    # --- dispatch
    for b, r in sorted(finished):
        n = vals.get((b, r, "UCFS-cmp-dispatch-new-edges-UCFS"), "0")
        if n not in ("0", None):
            hit = [(ln, l) for ln, l in prose if l.startswith("DISPATCH %s %s:" % (b, r[5:]))]
            if hit and prose_words(hit[0][1]) >= 12:
                ok("DISPATCH %s %s (%s new edges) explained at line %d" % (b, r[5:], n, hit[0][0]))
                print("JUDGE: dispatch line %d: %s %s" % (hit[0][0], b, r))
            else:
                ko("no line 'DISPATCH %s %s: ...' with >= 12 words for %s new edges" % (b, r[5:], n))

    # --- code references
    nref = 0
    for ln, l in prose:
        for m in REF.finditer(l):
            path, a, z, sym = m.group(1), int(m.group(2)), int(m.group(3) or m.group(2)), m.group(4)
            fp = os.path.join(ROOT, path)
            nref += 1
            if not os.path.isfile(fp) or z < a or z - a > 60:
                ko("line %d: reference %s:%d-%d does not resolve" % (ln, path, a, z))
                continue
            src = open(fp, encoding="utf-8", errors="replace").read().split("\n")[a - 1:z]
            if not any(re.search(r"(?<![\w$])%s(?![\w$])" % re.escape(sym), s) for s in src):
                ko("line %d: %s not on %s:%d-%d" % (ln, sym, path, a, z))
            else:
                print("JUDGE: reference line %d: %s:%d-%d#%s" % (ln, path, a, z, sym))
    ok("%d code references checked" % nref)

    # --- bibliography
    keys = set(l.strip() for l in open(os.path.join(ROOT, "acceptance", "E3", "bib_keys.txt")) if l.strip())
    cited = set()
    for ln, l in prose:
        for k in BIB.findall(l):
            if k in keys:
                cited.add(k)
            else:
                ko("line %d: %s is not a key of references.bib" % (ln, k))
    for k in REQUIRED_KEYS:
        (ok if k in cited else ko)("bib key %s cited" % k)

    # --- mentions
    for w in MENTIONS:
        (ok if w in text else ko)("mention %s" % w)

    # --- claim sweep
    body = " ".join(l for _, l in prose if l and not l.startswith("#") and not l.startswith("|")
                    and not l.startswith("EXAMPLE") and not l.startswith("DISPATCH"))
    sentences = re.split(r"(?<=[.!?;])\s+", body)
    nclaims = 0
    for s in sentences:
        low = " " + re.sub(r"`[^`]*`", " ", s).lower() + " "
        hits = [w for w in UNIVERSAL if re.search(r"(?<![\wА-Яа-яЁё])%s(?![\wА-Яа-яЁё])" % re.escape(w), low)]
        marked = "интерпретация" in s.lower()
        m = re.search(r"проверено:\s*(.*)", s)
        if m and (re.search(r"`[^`]+`", m.group(1)) or REF.search(m.group(1))):
            marked = True
        if BIB.search(s) and any(k in keys for k in BIB.findall(s)):
            marked = True
        if REF.search(s):
            marked = True
        if "проверено" in s.lower() or "интерпретация" in s.lower():
            nclaims += 1
            print("CLAIM: " + s.strip()[:300])
        if hits and not marked:
            ko("unmarked claim with %s: %s" % (hits, s.strip()[:200]))
    (ok if "интерпретация" in text else ko)("the word 'интерпретация' occurs")
    ok("%d marked sentences (CLAIM lines)" % nclaims)
    print("RESULT-PY: " + ("FAIL" if fails else "PASS"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
