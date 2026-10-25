#!/usr/bin/env python3
"""Checker of docs/ucfs-integration/ucfs-vs-spark.md against the committed results (E4-S7,
docs/ai/tickets/E4-S7.md).

Usage: python3 acceptance/E4/doc_check.py <doc.md> <results-dir>     (exit 0 = all checks pass)
<results-dir> holds runs.tsv, values.tsv, examples.tsv (scripts/ucfs/e4-bench.sh) and probe_jdk.txt (E4-S6).

Prose = the lines outside ``` fences that are not headings ("#"), table rows ("|"), EXAMPLE or DISPATCH
lines; sentences are split at . ! ? ; followed by a blank. Code spans (`...`) are not prose.
Checks:
  * results: runs.tsv covers exactly the 12 benchmarks of E4.md D3 (BENCHES) with the runs RUNS each;
    ucfs-ANALYSIS finished (status ok) on >= 2 benchmarks whose D3 coverage (tables.py T5) is >= 50 %;
    in every finished ucfs run the call-graph metrics are equal in the three views; a finished ucfs run
    with UCFS-cmp-MISSING or UCFS-cmp-UNEXPLAINED > 0 needs a prose line naming the benchmark and that class;
  * the section headings HEADINGS, in this order; the words of SECTION_MENTIONS inside their sections;
  * the six tables of acceptance/E4/tables.py on <results-dir> occur verbatim in the document, T5 and
    T6 inside the sections of TABLE_SECTION;
  * the "PROBE seam:" and "PROBE finished=" lines of probe_jdk.txt occur verbatim in the document;
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
  * sources: "проверено:" counts only when what follows it in the sentence has a code reference, a
    `command` in backticks that starts with "python3 acceptance/", "bash acceptance/", "bash scripts/" or
    "python3 scripts/", or a path into docs/ucfs-integration/e4-results/; a sentence with "проверено"
    and no such source fails (E4.md, lead decision M4);
  * claim sweep: every prose sentence with a universal or absolute word (UNIVERSAL) also carries a code
    reference, a bib key, the mark "интерпретация", or "проверено:" with a source as above; the word
    "интерпретация" occurs at least once;
  * numbers: every number of a prose sentence (digits outside code spans, code references and bib keys;
    number words of NUMBER_WORDS count as their digits) is in WHITELIST or is a value of the results:
    a value of values.tsv (also rounded to 3 and to 1 decimals) or a number in a cell of the six
    tables; when the sentence names benchmarks, the value must belong to one of them (its values.tsv
    rows or its table rows). A sentence marked "проверено:" with a source is exempt (it is a CLAIM line).
    Numbers are written as in the tables: digits without thousands separators, "." for decimals;
  * wording: no FORBIDDEN phrase (precision of UCFS against Spark is not a property of the solver,
    E4.md lead decision M1); a sentence with a COMPARATIVE word has at least one checked number.
Prints one "JUDGE:" line per example, dispatch line and code reference, one "CLAIM:" line per marked
sentence and one "NUMBER:" line per checked number with where it was found: the verifier judges all prose
of sections 2-6 and every one of these lines against the code and the tables (E3 lesson: the mechanics
check the marks, not the truth).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tables  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BENCHES = ["antlr", "bloat", "chart", "eclipse", "fop", "luindex", "lusearch", "pmd", "xalan", "checkstyle",
           "findbugs", "JPC"]
RUNS = ["insens", "ucfs-ANALYSIS", "ucfs-CALL_GRAPH", "cov-D3", "cov-JDK"]
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
            "ANALYSIS", "SeedCheck.java", "EmptyArrayProg"]
# words that must occur inside a section (number of the heading -> words)
SECTION_MENTIONS = {1: ["срез", "покрыт"], 2: ["CALL_GRAPH", "this", "Spark"],
                    3: ["следствие построения", "полнот", "фильтр"],
                    6: ["срез", "покрыт", "одно наблюдение", "probe_jdk.sh"]}
TABLE_SECTION = {"T5": 1, "T6": 2}
FORBIDDEN = [r"точнее", r"менее\s+точн", r"более\s+точн"]
COMPARATIVE = re.compile(r"(?<![\wА-Яа-яЁё])(быстрее|медленнее|полнее|лучше|хуже|(?:больше|меньше),?\s+чем|"
                         r"(?:больше|меньше)\s+(?:у\s+)?Spark)", re.I)
NUMBER_WORDS = {"четыре": "4", "четырёх": "4", "четырех": "4", "четырём": "4", "четырем": "4", "четырьмя": "4",
                "пять": "5", "пяти": "5", "пятью": "5", "шесть": "6", "шести": "6", "шестью": "6", "семь": "7",
                "семи": "7", "восемь": "8", "восьми": "8", "восемью": "8", "девять": "9", "девяти": "9",
                "десять": "10", "десяти": "10", "одиннадцать": "11", "одиннадцати": "11", "двенадцать": "12",
                "двенадцати": "12", "двадцать": "20", "двадцати": "20", "тридцать": "30", "тридцати": "30"}
# the numbers of the configuration that need no table: 12 benchmarks, 3 views, 2 bindings, threshold 50 %,
# TIMEOUT 900 s, XMX 16g, probe limit 540 s, 0 and 1
WHITELIST = {"0", "1", "2", "3", "12", "50", "900", "16", "540"}
NUM = re.compile(r"(?<![\w.,/:#@+\-])(\d+(?:\.\d+)?)(?![.,]?\d)(?![\w])")
# references that are not values: sections, steps, versions
NOT_A_VALUE = re.compile(r"(?:(?<![\wА-Яа-яЁё])(?:раздел\w*|пункт\w*|шаг\w*|глав\w*|п\.)\s+\d+(?:\s*(?:,|и|–|-)\s*\d+)*)"
                         r"|(?:(?:JDK|Java|Gradle|Python|Kotlin)\s+\d+(?:\.\d+)*)", re.I)
SOURCE_CMD = re.compile(r"`(?:python3|bash)\s+(?:acceptance|scripts)/[^`]+`")
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
    trun, tvals = tables.load(res)
    cov = {b: tables.coverage(trun, tvals, b) for b in BENCHES}
    okA = [b for b in BENCHES if runs.get((b, "ucfs-ANALYSIS"), [""] * 3)[2] == "ok" and (cov[b] or 0) >= tables.COVERED_PCT]
    (ok if len(okA) >= 2 else ko)("ucfs-ANALYSIS finished on %d benchmarks with D3 coverage >= %.0f %%: %s"
                                  % (len(okA), tables.COVERED_PCT, okA))
    finished = [(b, r) for (b, r), f in runs.items() if r.startswith("ucfs-") and f[2] == "ok"]
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

    # --- sections
    sec_of = {}
    cur = 0
    for ln, l in prose:
        m = re.match(r"^## (\d+)\. ", l)
        if m and l in HEADINGS:
            cur = int(m.group(1))
        sec_of[ln] = cur
    def section_text(n):
        return "\n".join(l for ln, l in prose if sec_of.get(ln) == n)
    for n, words in SECTION_MENTIONS.items():
        st = section_text(n)
        for w in words:
            (ok if w in st else ko)("section %d mentions %s" % (n, w))

    # --- tables
    rendered = tables.render(res)
    for n, t in rendered.items():
        (ok if t in text else ko)("table %s of tables.py %s the document" % (n, "is in" if t in text else "is not verbatim in"))
    for n, s in TABLE_SECTION.items():
        first = rendered[n].split("\n")[0]
        hit = [ln for ln, l in enumerate(lines, 1) if l == first]
        (ok if hit and sec_of.get(hit[0]) == s else ko)("table %s in section %d" % (n, s))

    # --- JDK probe lines
    pf = os.path.join(res, "probe_jdk.txt")
    plines = [l.rstrip("\n") for l in open(pf, errors="replace")] if os.path.isfile(pf) else []
    want = [l for l in plines if l.startswith("PROBE seam:") or l.startswith("PROBE finished=")]
    (ok if len(want) == 5 and all(l in lines for l in want) else ko)(
        "the PROBE seam/finished lines of probe_jdk.txt (%d) are in the document" % len(want))

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

    # --- sentences (with the line where their paragraph starts)
    sentences = []
    para, pstart = [], None
    for ln, l in prose + [(len(lines) + 1, "")]:
        if not l.strip() or l.startswith("#") or l.startswith("|") or l.startswith("EXAMPLE") or l.startswith("DISPATCH"):
            if para:
                for s in re.split(r"(?<=[.!?;])\s+", " ".join(para)):
                    sentences.append((pstart, s))
            para, pstart = [], None
            if l.startswith("DISPATCH"):
                sentences.append((ln, l))
            if l.startswith("EXAMPLE"):
                sentences.append((ln, l.split(" — ", 1)[-1] if " — " in l else l.split(" - ", 1)[-1]))
            continue
        if pstart is None:
            pstart = ln
        para.append(l.strip())

    # --- known numbers of the results
    def forms(v):
        out = {v}
        try:
            f = float(v)
            out |= {"%.3f" % f, "%.1f" % f}
            if f == int(f):
                out.add(str(int(f)))
        except ValueError:
            pass
        return out
    known = {b: set() for b in BENCHES}
    glob = set()
    for (b, r, k), v in vals.items():
        fs = forms(v)
        glob |= fs
        if b in known:
            known[b] |= fs
    for n, tb in rendered.items():
        for row in tb.split("\n")[2:]:
            cells = [c.strip() for c in row.strip("|").split("|")]
            nums = set()
            for c in cells[1:]:
                for x in re.findall(r"\d+(?:\.\d+)?", c):
                    nums |= forms(x)
            glob |= nums
            if cells and cells[0] in known:
                known[cells[0]] |= nums
    bench_re = re.compile(r"(?<![\w-])(%s)(?![\w-])" % "|".join(BENCHES))
    word_re = re.compile(r"(?<![\wА-Яа-яЁё])(%s)(?![\wА-Яа-яЁё])" % "|".join(sorted(NUMBER_WORDS, key=len, reverse=True)), re.I)

    # --- sources, claim sweep, numbers, wording
    nclaims = nnum = 0
    for ln, s in sentences:
        code_free = re.sub(r"`[^`]*`", " ", s)
        low = " " + code_free.lower() + " "
        hits = [w for w in UNIVERSAL if re.search(r"(?<![\wА-Яа-яЁё])%s(?![\wА-Яа-яЁё])" % re.escape(w), low)]
        sourced = False
        m = re.search(r"проверено:\s*(.*)", s)
        if m and (SOURCE_CMD.search(m.group(1)) or REF.search(m.group(1)) or "docs/ucfs-integration/e4-results/" in m.group(1)):
            sourced = True
        if "проверено" in s.lower() and not sourced:
            ko("line %d: 'проверено' without a source (a command from acceptance/ or scripts/, a results file or a code reference): %s"
               % (ln, s.strip()[:160]))
        marked = sourced or "интерпретация" in s.lower() or bool(REF.search(s)) \
            or (bool(BIB.search(s)) and any(k in keys for k in BIB.findall(s)))
        if "проверено" in s.lower() or "интерпретация" in s.lower():
            nclaims += 1
            print("CLAIM: line %d: %s" % (ln, s.strip()[:300]))
        if hits and not marked:
            ko("line %d: unmarked claim with %s: %s" % (ln, hits, s.strip()[:200]))
        for f in FORBIDDEN:
            if re.search(f, code_free, re.I):
                ko("line %d: forbidden wording /%s/ (precision is not a property of the solver, M1): %s" % (ln, f, s.strip()[:160]))
        # numbers
        # a code span that is only a number is a number of the prose
        bare = re.sub(r"`\s*(\d+(?:\.\d+)?)\s*%?\s*`", r" \1 ", s)
        bare = re.sub(r"`[^`]*`", " ", bare)
        bare = REF.sub(" ", bare)
        bare = BIB.sub(" ", bare)
        bare = NOT_A_VALUE.sub(" ", bare)
        nums = [(x, x) for x in NUM.findall(bare)] + [(w, NUMBER_WORDS[w.lower()]) for w in word_re.findall(bare)]
        named = set(bench_re.findall(bare))
        pool = set().union(*(known[b] for b in named)) if named else glob
        checked = 0
        for shown, x in nums:
            if x in WHITELIST:
                continue
            if sourced:
                print("NUMBER: line %d: %s (sentence marked 'проверено:' with a source; judge it)" % (ln, shown))
                checked += 1
                continue
            nnum += 1
            if x in pool:
                checked += 1
                print("NUMBER: line %d: %s found in the results of %s" % (ln, shown, ", ".join(sorted(named)) if named else "the tables/values"))
            else:
                ko("line %d: number %s is not a value of the results of %s: %s"
                   % (ln, shown, ", ".join(sorted(named)) if named else "any benchmark", s.strip()[:160]))
        if COMPARATIVE.search(code_free) and checked == 0 and not any(x in pool for _, x in nums if x not in WHITELIST):
            ko("line %d: comparative wording without a number of the results: %s" % (ln, s.strip()[:160]))
    (ok if "интерпретация" in text else ko)("the word 'интерпретация' occurs")
    ok("%d marked sentences (CLAIM lines), %d checked numbers" % (nclaims, nnum))
    print("RESULT-PY: " + ("FAIL" if fails else "PASS"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
