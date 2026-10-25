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
  * a sentence that names >= 2 benchmarks and has a COMPARATIVE word needs "проверено:" with a source (a
    list of benchmarks in a comparison is a claim the tables must back; the verifier judges it);
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
SECTION_MENTIONS = {
    1: ["срез", "покрыт", "медиан", "повтор", "прогрев", "доверительн", "минимальн", "RSS", "JVM"],
    2: ["ANALYSIS", "CALL_GRAPH", "this", "Spark", "одной JVM"],
    3: ["parse", "rsm", "export", "import"],
    4: ["RSS", "минимальн", "куч"],
    5: ["IQR", "CV", "ответ"],
    6: ["одно наблюдение", "probe-cg", "probe-jdk"],
    7: ["срез", "покрыт", "интерпретация"],
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
SOURCE_CMD = re.compile(r"`(?:python3|bash)\s+(?:acceptance|scripts)/[^`]+`")
UNIVERSAL = ["только", "никогда", "всегда", "все", "всех", "всем", "всё", "любой", "любая", "любое", "каждый",
             "каждая", "каждое", "каждого", "каждой", "всего", "гарантирует", "гарантированно", "точно", "ровно",
             "полностью", "никакой", "ни один", "ни одна", "ни одного", "only", "never", "always", "all", "any",
             "every", "each", "none", "exactly", "guarantee", "guarantees", "completely"]
CAUSAL = ["потому что", "поэтому", "из-за", "объясняется", "объясняет", "вызван", "вызвано", "связано с",
          "так как", "because", "due to"]
BIB = re.compile(r"\b([A-Z][A-Za-z]+(?:19|20)\d\d[A-Z][A-Za-z]*)\b")
REF = re.compile(r"`?([\w./-]+\.(?:java|kt|sh|py|gradle)):(\d+)(?:-(\d+))?#([\w$<>]+)`?")
STATUS_WORD = {"timeout": ["timeout", "таймаут", "не уложил"], "oom": ["oom", "OutOfMemoryError", "памят"],
               "error": ["error", "ошибк"], "skipped": ["skipped", "пропущ", "не запуска"]}
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

    # --- known numbers, per benchmark
    known = {b: set() for b in BENCHES}
    glob = set()
    for (b, run, rep), d in bench.v.items():
        for v in d.values():
            fs = forms(v)
            glob |= fs
            if b in known:
                known[b] |= fs
    extra_rows = []
    mhp = os.path.join(res, "minheap", "minheap.tsv")
    if os.path.isfile(mhp):
        extra_rows += e5lib.read_tsv(mhp)
    for p in ("probe-cg", "probe-jdk"):
        part = e5tables.Part(os.path.join(res, p))
        extra_rows += part.runs
        for (b, run, rep), d in part.v.items():
            for v in d.values():
                glob |= forms(v)
                if b in known:
                    known[b] |= forms(v)
    for r in bench.runs + extra_rows:
        for k, v in r.items():
            if k not in ("bench", "run", "status"):
                glob |= forms(v)
                if r.get("bench") in known:
                    known[r["bench"]] |= forms(v)
    for n, tb in rendered.items():
        for row in tb.split("\n")[3:]:
            cells = [c.strip() for c in row.strip("|").split("|")]
            nums = set()
            for c in cells[1:]:
                for x in re.findall(r"\d+(?:\.\d+)?", c):
                    nums |= forms(x)
            glob |= nums
            owner = next((c for c in cells if c in known), None)
            if owner:
                known[owner] |= nums
    word_re = re.compile(r"(?<![\wА-Яа-яЁё])(%s)(?![\wА-Яа-яЁё])" % "|".join(sorted(NUMBER_WORDS, key=len, reverse=True)), re.I)

    nclaims = nnum = 0
    for ln, s in sentences:
        code_free = re.sub(r"`[^`]*`", " ", s)
        low = " " + code_free.lower() + " "
        hits = [w for w in UNIVERSAL + CAUSAL if re.search(r"(?<![\wА-Яа-яЁё])%s(?![\wА-Яа-яЁё])" % re.escape(w), low)]
        m = re.search(r"проверено:\s*(.*)", s)
        sourced = bool(m and (SOURCE_CMD.search(m.group(1)) or REF.search(m.group(1))
                              or "docs/ucfs-integration/e5-results/" in m.group(1)
                              or "docs/ucfs-integration/e4-results/" in m.group(1)))
        if "проверено" in s.lower() and not sourced:
            ko("line %d: 'проверено' without a source: %s" % (ln, s.strip()[:160]))
        marked = sourced or "интерпретация" in s.lower() or bool(REF.search(s)) \
            or any(k in keys for k in BIB.findall(s))
        if "проверено" in s.lower() or "интерпретация" in s.lower():
            nclaims += 1
            print("CLAIM: line %d: %s" % (ln, s.strip()[:300]))
        if hits and not marked:
            ko("line %d: unmarked claim with %s: %s" % (ln, hits, s.strip()[:200]))
        for f in FORBIDDEN:
            if re.search(f, code_free, re.I):
                ko("line %d: forbidden wording /%s/: %s" % (ln, f, s.strip()[:160]))
        bare = re.sub(r"`\s*(\d+(?:\.\d+)?)\s*%?\s*`", r" \1 ", s)
        bare = re.sub(r"`[^`]*`", " ", bare)
        bare = REF.sub(" ", bare)
        bare = BIB.sub(" ", bare)
        bare = NOT_A_VALUE.sub(" ", bare)
        names = [(mm.start(), mm.group(1)) for mm in bench_re.finditer(bare)]
        nums = [(mm.start(), mm.group(1), mm.group(1)) for mm in NUM.finditer(bare)]
        nums += [(mm.start(), mm.group(1), NUMBER_WORDS[mm.group(1).lower()]) for mm in word_re.finditer(bare)]
        if len({b for _, b in names}) >= 2 and COMPARATIVE.search(code_free) and not sourced:
            ko("line %d: comparison over several benchmarks without 'проверено:' and a source: %s" % (ln, s.strip()[:160]))
        checked = 0
        for at, shown, x in sorted(nums):
            if x in WHITELIST:
                continue
            if sourced:
                print("NUMBER: line %d: %s (sentence marked 'проверено:' with a source; judge it)" % (ln, shown))
                checked += 1
                continue
            nnum += 1
            before = [b for p, b in names if p < at]
            after = [b for p, b in names if p > at]
            owner = before[-1] if before else (after[0] if after else None)
            pool = known[owner] if owner else glob
            if x in pool:
                checked += 1
                print("NUMBER: line %d: %s found in the results of %s" % (ln, shown, owner or "the tables/values"))
            else:
                ko("line %d: number %s is not a value of %s: %s" % (ln, shown, owner or "the results", s.strip()[:160]))
        if COMPARATIVE.search(code_free) and checked == 0:
            ko("line %d: comparative wording without a checked number: %s" % (ln, s.strip()[:160]))
    (ok if "интерпретация" in text else ko)("the word 'интерпретация' occurs")
    ok("%d marked sentences (CLAIM lines), %d checked numbers" % (nclaims, nnum))
    print("RESULT-PY: " + ("FAIL" if fails else "PASS"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
