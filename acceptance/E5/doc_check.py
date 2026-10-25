#!/usr/bin/env python3
"""Checker of docs/ucfs-integration/e5-benchmarks.md against the committed E5 results (E5-S6,
docs/ai/tickets/E5-S6.md). Built on acceptance/E4/doc_check.py; the number rule binds every number to one
benchmark (E9 backlog #41).

Usage: python3 acceptance/E5/doc_check.py <doc.md> <e5-results-dir>     (exit 0 = all checks pass)

Prose = the lines outside ``` fences that are not headings ("#") or table rows ("|"); sentences are split at
. ! ? ; followed by a blank. Code spans (`...`) are not prose, except a code span that holds only a number.
Checks:
  * results: bench/meta.tsv has reps >= 5 and host-kind vm or local; if local, the document says
    "локальный прогон" in sections 1 and 7 (the lead's fallback, E5.md); every (bench, run) with a
    measured repetition that is not ok is named in a prose sentence together with its status word;
  * the section headings HEADINGS in this order and the words of SECTION_MENTIONS inside their sections;
  * the eight tables of acceptance/E5/e5tables.py occur verbatim, each in its section (TABLE_SECTION);
  * every answer key that varies over repetitions (table T7) is named in section 5;
  * code references `<repo path>:<line>#<symbol>` or `<path>:<a>-<b>#<symbol>` (<= 61 lines) resolve;
  * bibliography: tokens shaped like a bib key are keys of acceptance/E3/bib_keys.txt; REQUIRED_KEYS cited;
  * sources: "проверено:" counts only with a code reference, a `command` in backticks that starts with
    "python3 acceptance/", "bash acceptance/", "bash scripts/" or "python3 scripts/", or a path into
    docs/ucfs-integration/e5-results/ or docs/ucfs-integration/e4-results/; "проверено" without a source fails;
  * claim sweep: a sentence with a word of UNIVERSAL or CAUSAL carries a code reference, a bib key,
    "интерпретация" or "проверено:" with a source;
  * numbers (E9 #41): every number of a sentence (digits outside code, references, bib keys, section and
    version numbers; number words count) is in WHITELIST, or the sentence is "проверено:" with a source
    (printed as NUMBER for the verifier), or it is a value of ONE benchmark: the benchmark name closest
    before the number in the sentence (if none before, the closest after); the value must be in that
    benchmark's rows of the tables (cells after the first) or its values (bench/values.tsv, minheap.tsv,
    probes; rounded to 0-3 decimals; a table row belongs to the first of its cells that is a benchmark name).
    A sentence without a benchmark name: the number must be a cell of a
    table or a value of the results;
  * a number in a sentence that names a run or binding (insens, ucfs-ANALYSIS, ucfs-CALL_GRAPH, ANALYSIS,
    CALL_GRAPH) belongs to the (benchmark, run) closest to it: it must be in the rows of that benchmark and
    run (or binding) of the tables, in its values, or in the run-independent row of T2 (E9 #41, MINOR-2);
  * a factor "в N раз(а)" is not whitelisted: N must be a cell of the columns UCFS/Spark or kernel/Spark of
    T3 in the row(s) of the benchmark (and binding) it belongs to; "на порядок/порядки" (на поряд...) only with
    "проверено:" and a source (MINOR-2);
  * UCFS against Spark (MAJOR-1): a sentence with "UCFS", "Spark" and a time comparative (быстрее, медленнее,
    дольше) or a memory comparative (экономнее, меньше/больше памяти) names a benchmark and holds a number of
    its T3 row (time) or T6 row (memory); the direction must agree with the table: "UCFS быстрее Spark" (or
    "Spark медленнее UCFS") only where the median UCFS/Spark of every row meant (the binding named, else every
    row with n > 0) is < 1, "медленнее/дольше" only where it is > 1, "UCFS экономнее Spark" only where the
    minimum heap minus insens is < 0 (a "не" right before the comparative leaves the direction to the
    verifier); sections 2 and 7 hold the caveat CAVEAT (a sentence with it is exempt from the comparative
    rules) and name pureRun (section 2 also Jimple): Spark's time includes the lazy building of the method
    bodies, the PAG and the call graph, UCFS solves on the finished global PAG;
  * a sentence with a COMPARATIVE word that names a benchmark with fewer than 6 ok repetitions in the T3
    row(s) meant has no median interval behind it and fails (MINOR-5);
  * a sentence of section 3 that says a phase dominates (DOMINANT) names only benchmarks whose T4 total is
    >= 5000 ms in the row(s) meant: on short UCFS parts the phases show the cold JVM (MINOR-6);
  * a difference of minimum heaps of T6 below 32 MB in absolute value is quoted only with "в пределах шага"
    (each search has the step 16 MB; MINOR-7); every benchmark with a T6 16384/minheap below 4 is named in
    section 4 or 7 in a sentence with "кратн" (the heap of the runs is then less than 4 x the minimum heap,
    Blackburn2025Rethinking H2; MINOR-4); every minimum-heap search with a status other than ok is named in
    section 4 together with its status word;
  * load1 is a 1-minute average that still holds the previous run: a sentence with load1 has no causal word
    (MAJOR-7, load1 only descriptive);
  * a sentence that names >= 2 benchmarks and has a COMPARATIVE word needs "проверено:" with a source (a
    list of benchmarks in a comparison is a claim the tables must back; the verifier judges it);
  * "проверено:" counts with a command only if the script of the command exists in the repository;
  * a sentence with a COMPARATIVE word has at least one checked number; no FORBIDDEN phrase.
Prints "JUDGE:" (code references), "CLAIM:" (marked sentences) and "NUMBER:" (checked numbers, with the
benchmark and where found): the verifier judges all prose of sections 2-7 and these lines.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import e5lib  # noqa: E402
import e5tables  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BENCHES = e5lib.BENCHES
HEADINGS = [
    "## 1. Методика и конфигурация",
    "## 2. Время: UCFS против Spark",
    "## 3. Время UCFS по фазам",
    "## 4. Память",
    "## 5. Разброс времени и ответа",
    "## 6. Пробы за пределами бюджета",
    "## 7. Ограничения и угрозы валидности",
    "## 8. Воспроизведение",
]
REQUIRED_KEYS = ["He2022Qilin", "Lhotak2003Scaling", "Blackburn2025Rethinking"]
CAVEAT = "не значит, что UCFS быстрее решает ту же задачу"
SECTION_MENTIONS = {
    1: ["срез", "покрыт", "медиан", "повтор", "прогрев", "доверительн", "минимальн", "RSS", "JVM"],
    2: ["ANALYSIS", "CALL_GRAPH", "this", "Spark", "одной JVM", "pureRun", "Jimple", CAVEAT],
    3: ["parse", "rsm", "export", "import"],
    4: ["RSS", "минимальн", "куч"],
    5: ["IQR", "CV", "ответ"],
    6: ["одно наблюдение", "probe-cg", "probe-jdk"],
    7: ["срез", "покрыт", "интерпретация", "pureRun", CAVEAT],
    8: ["e5-full.sh", "e5-vm-setup.sh", "e5tables.py"],
}
TABLE_SECTION = {"T1": 1, "T2": 1, "T3": 2, "T4": 3, "T6": 4, "T5": 5, "T7": 5, "T8": 6}
FORBIDDEN = [r"точнее", r"менее\s+точн", r"более\s+точн"]
COMPARATIVE = re.compile(r"(?<![\wА-Яа-яЁё])(быстрее|медленнее|дольше|короче|лучше|хуже|экономнее|"
                         r"(?:больше|меньше),?\s+чем|(?:больше|меньше)\s+(?:у\s+)?Spark|в\s+\S+\s+раз)", re.I)
NUMBER_WORDS = {"четыре": "4", "четырёх": "4", "четырех": "4", "пять": "5", "пяти": "5", "шесть": "6", "шести": "6",
                "семь": "7", "семи": "7", "восемь": "8", "восьми": "8", "девять": "9", "девяти": "9", "десять": "10",
                "десяти": "10", "одиннадцать": "11", "одиннадцати": "11", "двенадцать": "12", "двенадцати": "12",
                "двадцать": "20", "двадцати": "20", "тридцать": "30", "тридцати": "30"}
# configuration numbers that need no table: 0-3, 12 benchmarks, 6 covered, 10 repetitions (+1 warm-up = 11),
# 50 % coverage threshold, 95 % confidence, TIMEOUT 900 s, XMX 16g, probes 3600 s and 52g, min heap 64..16384
# MB step 16 (confirmed with 32), factor 3, 100 (percent)
WHITELIST = {"0", "1", "2", "3", "5", "6", "10", "11", "12", "16", "32", "50", "52", "64", "95", "100", "900",
             "3600", "16384"}
NUM = re.compile(r"(?<![\w.,/:#@+\-])(\d+(?:\.\d+)?)(?![.,]?\d)(?![\w])")
NOT_A_VALUE = re.compile(r"(?:(?<![\wА-Яа-яЁё])(?:раздел\w*|пункт\w*|шаг\w*|глав\w*|табл\w*|п\.|T|E|S)\s*\d+"
                         r"(?:\s*(?:,|и|–|-)\s*\d+)*)"
                         r"|(?:(?:JDK|Java|Gradle|Python|Kotlin|Ubuntu|Temurin)\s+\d+(?:\.\d+)*)", re.I)
SOURCE_CMD = re.compile(r"`(?:python3|bash)\s+((?:acceptance|scripts)/[^`\s]+)[^`]*`")
UNIVERSAL = ["только", "никогда", "всегда", "все", "всех", "всем", "всё", "любой", "любая", "любое", "каждый",
             "каждая", "каждое", "каждого", "каждой", "всего", "гарантирует", "гарантированно", "точно", "ровно",
             "полностью", "никакой", "ни один", "ни одна", "ни одного", "only", "never", "always", "all", "any",
             "every", "each", "none", "exactly", "guarantee", "guarantees", "completely"]
CAUSAL = ["потому что", "поэтому", "из-за", "объясняется", "объясняет", "вызван", "вызвано", "связано с",
          "так как", "because", "due to"]
BIB = re.compile(r"\b([A-Z][A-Za-z]+(?:19|20)\d\d[A-Z][A-Za-z]*)\b")
REF = re.compile(r"`?([\w./-]+\.(?:java|kt|sh|py|gradle)):(\d+)(?:-(\d+))?#([\w$<>]+)`?")
STATUS_WORD = {"timeout": ["timeout", "таймаут", "не уложил"], "oom": ["oom", "OutOfMemoryError", "памят"],
               "error": ["error", "ошибк"], "skipped": ["skipped", "пропущ", "не запуска"],
               "killed": ["killed", "убит"], "unconfirmed": ["unconfirmed", "не подтвержд"],
               "differs": ["differs", "другой ответ"], "le-lo": ["le-lo", "64 MB"]}
RUN_RE = re.compile(r"(?<![\w-])(ucfs-ANALYSIS|ucfs-CALL_GRAPH|insens|ANALYSIS|CALL_GRAPH)(?![\w-])")
TIME_CMP = re.compile(r"(?<![\wА-Яа-яЁё])(не\s+)?(быстрее|медленнее|дольше)(?![\wА-Яа-яЁё])", re.I)
MEM_CMP = re.compile(r"(?<![\wА-Яа-яЁё])(не\s+)?(экономнее|меньше\s+памяти|больше\s+памяти)(?![\wА-Яа-яЁё])", re.I)
FACTOR = re.compile(r"(?<![\wА-Яа-яЁё])в\s+(\d+(?:\.\d+)?)\s+раз", re.I)
ORDER_WORDS = re.compile(r"(?<![\wА-Яа-яЁё])на\s+поряд\w*", re.I)
DOMINANT = re.compile(r"доминир|основн\w*\s+(?:часть|дол)|большую\s+часть|львин|преоблада", re.I)
fails = []


def ok(m):
    print("PASS: " + m)


def ko(m):
    print("FAIL: " + m)
    fails.append(m)


def forms(v):
    out = {v}
    try:
        f = float(v)
    except ValueError:
        return out
    for d in range(4):
        out.add(("%." + str(d) + "f") % f)
    if f == int(f):
        out.add(str(int(f)))
    return out


def main():
    doc_path, res = sys.argv[1], sys.argv[2]
    text = open(doc_path, encoding="utf-8").read()
    lines = text.split("\n")
    prose, fenced = [], False
    for i, l in enumerate(lines):
        if l.strip().startswith("```"):
            fenced = not fenced
            continue
        if not fenced:
            prose.append((i + 1, l))

    bench = e5tables.Part(os.path.join(res, "bench"))
    meta = bench.meta
    # --- headings and sections
    heads = [l for _, l in prose if l.startswith("## ")]
    pos = [heads.index(h) if h in heads else -1 for h in HEADINGS]
    (ok if -1 not in pos and pos == sorted(pos) else ko)("the %d section headings in order %s" % (len(HEADINGS), pos))
    sec_of, cur = {}, 0
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

    # --- results and host
    try:
        reps = int(meta.get("reps", "0"))
    except ValueError:
        reps = 0
    (ok if reps >= 5 and meta.get("host-kind") in ("vm", "local") else ko)(
        "bench/meta.tsv: reps %s, host-kind %s" % (meta.get("reps"), meta.get("host-kind")))
    if meta.get("host-kind") == "local":
        for n in (1, 7):
            (ok if "локальный прогон" in section_text(n) else ko)("host-kind local: section %d says 'локальный прогон'" % n)

    # --- tables
    rendered = e5tables.render(res)
    for n, t in rendered.items():
        (ok if t in text else ko)("table %s of e5tables.py %s the document" % (n, "is in" if t in text else "is not verbatim in"))
    for n, s in TABLE_SECTION.items():
        first = rendered[n].split("\n")[0]
        hit = [ln for ln, l in enumerate(lines, 1) if l == first]
        (ok if hit and sec_of.get(hit[0]) == s else ko)("table %s in section %d" % (n, s))

    # --- sentences
    sentences, para, pstart = [], [], None
    for ln, l in prose + [(len(lines) + 1, "")]:
        if not l.strip() or l.startswith("#") or l.startswith("|") or l.startswith("<!--"):
            if para:
                for s in re.split(r"(?<=[.!?;])\s+", " ".join(para)):
                    sentences.append((pstart, s))
            para, pstart = [], None
            continue
        if pstart is None:
            pstart = ln
        para.append(l.strip())

    # --- non-ok statuses named in prose
    bench_re = re.compile(r"(?<![\w-])(%s)(?![\w-])" % "|".join(BENCHES))
    for b in bench.benches():
        for run in e5lib.RUNS:
            sts = {r["status"] for r in bench.measured(b, run)} - {"ok"}
            if not bench.measured(b, run) and "%s:%s" % (b, run) in meta.get("skip", "").split():
                sts = {"skipped"}
            for st in sorted(sts):
                words = STATUS_WORD.get(st, [st])
                hit = [ln for ln, s in sentences if b in bench_re.findall(s) and any(w.lower() in s.lower() for w in words)]
                (ok if hit else ko)("%s %s status %s %s" % (b, run, st, "named at line %d" % hit[0] if hit else "not named in prose"))

    # --- varying answer keys named in section 5
    s5 = section_text(5)
    for row in rendered["T7"].split("\n")[3:]:
        cells = [c.strip() for c in row.strip("|").split("|")]
        if len(cells) >= 5 and ":" in cells[4]:
            for k in cells[4].split(":", 1)[1].split(","):
                (ok if k.strip() in s5 else ko)("varying key %s of %s %s named in section 5" % (k.strip(), cells[0], cells[1]))

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

    # --- known numbers: per benchmark and per (benchmark, run)
    RUN_OF = {"ANALYSIS": "ucfs-ANALYSIS", "CALL_GRAPH": "ucfs-CALL_GRAPH"}
    known = {b: set() for b in BENCHES}
    known_run, bench_only = {}, {b: set() for b in BENCHES}
    glob = set()

    def add(b, run, fs):
        glob.update(fs)
        if b in known:
            known[b].update(fs)
            if run:
                known_run.setdefault((b, RUN_OF.get(run, run)), set()).update(fs)
            else:
                bench_only[b].update(fs)
    for (b, run, rep), d in bench.v.items():
        for v in d.values():
            add(b, run, forms(v))
    extra_rows = []
    for f in ("minheap.tsv", "steps.tsv"):
        mhp = os.path.join(res, "minheap", f)
        if os.path.isfile(mhp):
            extra_rows += e5lib.read_tsv(mhp)
    for p in ("probe-cg", "probe-jdk"):
        part = e5tables.Part(os.path.join(res, p))
        extra_rows += part.runs
        for (b, run, rep), d in part.v.items():
            for v in d.values():
                add(b, run, forms(v))
    for r in bench.runs + extra_rows:
        for k, v in r.items():
            if k not in ("bench", "run", "status"):
                add(r.get("bench"), r.get("run"), forms(v))
    rowinfo = {}
    for n, tb in rendered.items():
        tl = tb.split("\n")
        hdr = [c.strip() for c in tl[1].strip("|").split("|")]
        for row in tl[3:]:
            cells = [c.strip() for c in row.strip("|").split("|")]
            nums = set()
            for c in cells[1:]:
                for x in re.findall(r"\d+(?:\.\d+)?", c):
                    nums |= forms(x)
            owner = next((c for c in cells if c in known), None)
            orun = next((RUN_OF.get(c, c) for c in cells if RUN_RE.fullmatch(c)), None)
            if owner:
                add(owner, orun, nums)
                rowinfo.setdefault(n, {})[(owner, orun)] = dict(zip(hdr, cells))
            else:
                glob.update(nums)
    T3, T4, T6 = rowinfo.get("T3", {}), rowinfo.get("T4", {}), rowinfo.get("T6", {})

    def first_num(c, signed=False):
        mm = re.match(r"(-?\d+(?:\.\d+)?)" if signed else r"(\d+(?:\.\d+)?)", c or "")
        return float(mm.group(1)) if mm else None

    def rows_meant(table, b, runs_named):
        """rows of table (T3/T4: keyed by ucfs run) for benchmark b: those of the runs named, else those with n > 0"""
        rows = [(r, info) for (bb, r), info in table.items() if bb == b and r != "insens"]
        if runs_named:
            return [(r, info) for r, info in rows if r in runs_named]
        return [(r, info) for r, info in rows if info.get("n", "0") not in ("0", "-")]

    def cells_nums(rows, cols=None):
        out = set()
        for _, info in rows:
            for k, c in info.items():
                if cols is None or k in cols:
                    for x in re.findall(r"\d+(?:\.\d+)?", c):
                        out |= forms(x)
        return out
    low_mult = []
    for (b, r), info in T6.items():
        mult = first_num(info.get("16384/minheap"))
        if mult is not None and mult < 4:
            low_mult.append(b)
    word_re = re.compile(r"(?<![\wА-Яа-яЁё])(%s)(?![\wА-Яа-яЁё])" % "|".join(sorted(NUMBER_WORDS, key=len, reverse=True)), re.I)

    nclaims = nnum = 0
    for ln, s in sentences:
        code_free = re.sub(r"`[^`]*`", " ", s)
        low = " " + code_free.lower() + " "
        hits = [w for w in UNIVERSAL + CAUSAL if re.search(r"(?<![\wА-Яа-яЁё])%s(?![\wА-Яа-яЁё])" % re.escape(w), low)]
        m = re.search(r"проверено:\s*(.*)", s)
        sourced = bool(m and (any(os.path.isfile(os.path.join(ROOT, c.group(1))) for c in SOURCE_CMD.finditer(m.group(1)))
                              or REF.search(m.group(1))
                              or "docs/ucfs-integration/e5-results/" in m.group(1)
                              or "docs/ucfs-integration/e4-results/" in m.group(1)))
        if "проверено" in s.lower() and not sourced:
            ko("line %d: 'проверено' without a source (or its script does not exist): %s" % (ln, s.strip()[:160]))
        marked = sourced or "интерпретация" in s.lower() or bool(REF.search(s)) \
            or any(k in keys for k in BIB.findall(s))
        if "проверено" in s.lower() or "интерпретация" in s.lower():
            nclaims += 1
            print("CLAIM: line %d: %s" % (ln, s.strip()[:300]))
        if hits and not marked:
            ko("line %d: unmarked claim with %s: %s" % (ln, hits, s.strip()[:200]))
        causal = [w for w in CAUSAL if re.search(r"(?<![\wА-Яа-яЁё])%s(?![\wА-Яа-яЁё])" % re.escape(w), low)]
        if "load1" in s and causal:
            ko("line %d: load1 is descriptive only, no causal wording %s: %s" % (ln, causal, s.strip()[:160]))
        for f in FORBIDDEN:
            if re.search(f, code_free, re.I):
                ko("line %d: forbidden wording /%s/: %s" % (ln, f, s.strip()[:160]))
        if ORDER_WORDS.search(code_free) and not sourced:
            ko("line %d: 'на порядок' without 'проверено:' and a source: %s" % (ln, s.strip()[:160]))
        bare = re.sub(r"`\s*(\d+(?:\.\d+)?)\s*%?\s*`", r" \1 ", s)
        bare = re.sub(r"`[^`]*`", " ", bare)
        bare = REF.sub(" ", bare)
        bare = BIB.sub(" ", bare)
        bare = NOT_A_VALUE.sub(" ", bare)
        names = [(mm.start(), mm.group(1)) for mm in bench_re.finditer(bare)]
        runs_at = [(mm.start(), RUN_OF.get(mm.group(1), mm.group(1))) for mm in RUN_RE.finditer(bare)]
        named = sorted({b for _, b in names}, key=BENCHES.index)
        runs_named = {r for _, r in runs_at}
        nums = [(mm.start(), mm.group(1), mm.group(1)) for mm in NUM.finditer(bare)]
        nums += [(mm.start(), mm.group(1), NUMBER_WORDS[mm.group(1).lower()]) for mm in word_re.finditer(bare)]
        xs = {x for _, _, x in nums}
        if len(named) >= 2 and COMPARATIVE.search(code_free) and not sourced:
            ko("line %d: comparison over several benchmarks without 'проверено:' and a source: %s" % (ln, s.strip()[:160]))

        def owner_of(at, pairs):
            before = [b for p, b in pairs if p < at]
            after = [b for p, b in pairs if p > at]
            return before[-1] if before else (after[0] if after else None)
        # factors "в N раз": only cells of the ratio columns of T3
        factors = {}
        for fm in FACTOR.finditer(bare):
            factors[fm.start(1)] = fm.group(1)
        for at, x in factors.items():
            ob = owner_of(at, names)
            allowed = cells_nums(rows_meant(T3, ob, runs_named), ("UCFS/Spark", "kernel/Spark")) if ob else set()
            if x in allowed and not sourced:
                print("NUMBER: line %d: factor %s = a ratio of T3 for %s" % (ln, x, ob))
            elif not sourced:
                ko("line %d: factor 'в %s раз' is not a UCFS/Spark or kernel/Spark cell of T3 for %s: %s" % (
                    ln, x, ob or "a named benchmark", s.strip()[:160]))
        # UCFS against Spark (MAJOR-1); the fixed caveat itself is exempt
        caveat = CAVEAT in s
        if "UCFS" in code_free and "Spark" in code_free and not caveat:
            for rx, table, kind in ((TIME_CMP, T3, "time"), (MEM_CMP, T6, "memory")):
                cm = rx.search(code_free)
                if not cm:
                    continue
                if not named:
                    ko("line %d: UCFS against Spark (%s) without a benchmark: %s" % (ln, kind, s.strip()[:160]))
                    continue
                rows = [x for b in named for x in (rows_meant(T3, b, runs_named) if kind == "time" else
                        [(r, info) for (bb, r), info in T6.items() if bb == b and r != "insens"
                         and (not runs_named or r in runs_named)])]
                if not xs & cells_nums(rows):
                    ko("line %d: UCFS against Spark (%s) without a number of the %s row(s) of %s: %s" % (
                        ln, kind, "T3" if kind == "time" else "T6", named, s.strip()[:160]))
                if cm.group(1):
                    continue  # "не быстрее": the direction is judged by the verifier
                # the subject of the comparative: the closer of UCFS / Spark before it (else the first after)
                pre = code_free[:cm.start()]
                iu, isp = pre.rfind("UCFS"), pre.rfind("Spark")
                if iu == -1 and isp == -1:
                    subj = "UCFS" if code_free.find("UCFS") < code_free.find("Spark") else "Spark"
                else:
                    subj = "UCFS" if iu > isp else "Spark"
                word = cm.group(2).lower()
                ucfs_less = (subj == "UCFS") == (word in ("быстрее", "экономнее") or word.startswith("меньше"))
                for r, info in rows:
                    v = first_num(info.get("UCFS/Spark")) if kind == "time" else first_num(info.get("min heap - insens MB"), True)
                    if v is None:
                        continue
                    if kind == "time" and (v >= 1 if ucfs_less else v <= 1):
                        ko("line %d: '%s ... %s' but UCFS/Spark of %s %s is %s: %s" % (ln, subj, word, info.get("bench"), r, v, s.strip()[:120]))
                    if kind == "memory" and (v >= 0 if ucfs_less else v <= 0):
                        ko("line %d: '%s ... %s' but min heap - insens of %s %s is %s: %s" % (ln, subj, word, info.get("bench"), r, v, s.strip()[:120]))
        # comparisons need a median interval: n >= 6 (MINOR-5)
        if COMPARATIVE.search(code_free) and not caveat:
            for b in named:
                small = [(r, info.get("n")) for r, info in rows_meant(T3, b, runs_named)
                         if (first_num(info.get("n")) or 0) < 6]
                if small:
                    ko("line %d: comparison on %s with n < 6 %s (no interval of the median): %s" % (ln, b, small, s.strip()[:120]))
        # dominant phase only where the UCFS total >= 5 s (MINOR-6)
        if sec_of.get(ln) == 3 and DOMINANT.search(code_free):
            for b in named:
                short = [(r, info.get("total")) for r, info in rows_meant(T4, b, runs_named)
                         if (first_num(info.get("total")) or 0) < 5000]
                if short:
                    ko("line %d: dominant phase on %s with total < 5000 ms %s: %s" % (ln, b, short, s.strip()[:120]))
        checked = 0
        for at, shown, x in sorted(nums):
            if at in factors:
                checked += 1
                continue
            if x in WHITELIST:
                continue
            if sourced:
                print("NUMBER: line %d: %s (sentence marked 'проверено:' with a source; judge it)" % (ln, shown))
                checked += 1
                continue
            nnum += 1
            owner = owner_of(at, names)
            orun = owner_of(at, runs_at) if owner else None
            if owner and orun:
                pool, where = known_run.get((owner, orun), set()) | bench_only[owner], "%s %s" % (owner, orun)
            else:
                pool, where = (known[owner] if owner else glob), owner or "the tables/values"
            if x in pool:
                checked += 1
                print("NUMBER: line %d: %s found in the results of %s" % (ln, shown, where))
            else:
                ko("line %d: number %s is not a value of %s: %s" % (ln, shown, where, s.strip()[:160]))
            # a difference of minimum heaps below 32 MB is within the step (MINOR-7)
            if owner and sec_of.get(ln) == 4 and "в пределах шага" not in s:
                for (bb, r), info in T6.items():
                    d = first_num(info.get("min heap - insens MB"), True)
                    if bb == owner and d is not None and abs(d) < 32 and x in forms(str(int(abs(d)))) | forms(str(int(d))):
                        ko("line %d: difference %s MB of %s %s < 32 MB without 'в пределах шага': %s" % (
                            ln, shown, bb, r, s.strip()[:120]))
        if COMPARATIVE.search(code_free) and checked == 0 and not caveat:
            ko("line %d: comparative wording without a checked number: %s" % (ln, s.strip()[:160]))
    # heap of the runs below 4 x minimum heap named (MINOR-4); minimum-heap searches not ok named (section 4)
    for b in sorted(set(low_mult), key=BENCHES.index):
        hit = [ln for ln, s in sentences if sec_of.get(ln) in (4, 7) and b in bench_re.findall(s) and "кратн" in s]
        (ok if hit else ko)("%s: 16384/minheap < 4 %s" % (b, "named at line %d" % hit[0] if hit else "not named in sections 4/7 with 'кратн'"))
    mhp = os.path.join(res, "minheap", "minheap.tsv")
    for r in e5lib.read_tsv(mhp) if os.path.isfile(mhp) else []:
        if r["status"] == "ok":
            continue
        st = r["status"][4:] if r["status"].startswith("ref-") else r["status"]
        words = STATUS_WORD.get(st, [st])
        hit = [ln for ln, s in sentences if sec_of.get(ln) == 4 and r["bench"] in bench_re.findall(s)
               and any(w.lower() in s.lower() for w in words + [r["status"]])]
        (ok if hit else ko)("minimum heap %s %s status %s %s" % (r["bench"], r["run"], r["status"],
                                                                "named at line %d" % hit[0] if hit else "not named in section 4"))
    (ok if "интерпретация" in text else ko)("the word 'интерпретация' occurs")
    ok("%d marked sentences (CLAIM lines), %d checked numbers" % (nclaims, nnum))
    print("RESULT-PY: " + ("FAIL" if fails else "PASS"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
