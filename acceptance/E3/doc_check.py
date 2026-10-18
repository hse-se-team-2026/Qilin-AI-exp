#!/usr/bin/env python3
"""Checker of docs/ucfs-integration/ucfs-pointsto.md (E3-S5, docs/ai/tickets/E3-S5.md).

Usage: python3 acceptance/E3/doc_check.py <doc.md> <excerpts-out.md>
Exit 0 = all checks pass, 1 = some check failed.

Code references (the only accepted forms):
  * Qilin-AI-exp: `<repo path>:<line>#<symbol>` or `<repo path>:<from>-<to>#<symbol>`, checked at the
    commit of the line `pin: <40-hex>` (first 15 lines). The pin descends from the E3 base ecc2a25,
    is an ancestor of HEAD and already contains the E3 code (PagExport, PointsToGrammar, UcfsPointsTo);
  * UCFS: `ucfs:<path>:<line>#<symbol>` (same range rule), checked in the UCFS clone .ucfs/src at the
    commit of the line `ucfs-pin: <40-hex>`, which must equal ucfsCommit of gradle.properties.
A reference is valid when the file exists at the pinned commit, the lines exist, the range has at most
61 lines and <symbol> occurs on them as a whole word in code, not only in a comment (critic-E3 m7). A
`<file>.(kt|java|gradle|py|sh):<n>` mention without `#<symbol>` is a FAIL.

On top of existence:
  * every line with a reference carries >= 8 words of prose outside code spans;
  * every mandatory anchor (REQUIRED) has its own table row (a line starting with '|') that holds
    exactly this one reference and >= 8 words of prose, and the referenced range holds the
    DECLARATION of the symbol (fun/class/object/interface in Kotlin; method/constructor or type in
    Java), not a call site;
  * the mandatory section headings (HEADINGS) are present, in this order;
  * bibliography: every token shaped like a bib key (AuthorYYYYWord) is a key of
    acceptance/E3/bib_keys.txt (= the keys of docs/ai/articles_pdf/references.bib), and the keys in
    REQUIRED_KEYS are cited;
  * mandatory mentions (MENTIONS): test classes/cases, the reproduction commands, R1..R5, ROOT, the
    second export mode; in sections 5-6 (SECTION56) the counters of the "new" edges made by the
    solver and one sentence with pairsWithoutDerivedNew and a share in percent (E3.md B1);
  * claim sweep (E2 lesson, critic-E3 M2): every sentence of prose (not a heading, not in a fenced
    block) that contains a universal or absolute word (UNIVERSAL: only/never/always/all/any/every/
    each/none/exactly/guarantee..., только/никогда/всегда/все/любой/каждый/всего/гарантирует/точно/
    ровно/полностью/...) also carries, in the same sentence, a code reference, a bib key, or a mark:
    "интерпретация", or "проверено:" followed by a code reference or a `command` in backticks. A bare
    "проверено" is no mark;
  * the word "интерпретация" occurs at least once.
The script writes <excerpts-out.md> (every reference with its doc line and the pinned code), prints
one line "JUDGE:" per reference that is not a mandatory anchor and one line "CLAIM:" per sentence that
carries a mark: the verifier judges all anchors, every JUDGE line and every CLAIM line (critic-E3 m6).
"""
import os
import re
import subprocess
import sys

E3_BASE = "ecc2a25"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
UCFS_SRC = os.path.join(ROOT, ".ucfs", "src")
U = "solver/src/main/kotlin/org/ucfs/"
K = "qilin.ucfs/src/main/kotlin/qilin/ucfs/"
C = "qilin.core/src/qilin/core/"

# (repo, path, symbol, kind); repo: "ucfs" or "qilin"; kind: m = function/method, t = type
REQUIRED = [
    # UCFS: grammar -> RSM
    ("ucfs", U + "grammar/combinator/Grammar.kt", "buildRsm", "m"),
    ("ucfs", U + "rsm/RsmState.kt", "buildRsmBox", "m"),
    ("ucfs", U + "grammar/combinator/regexp/Regexp.kt", "derive", "m"),
    # UCFS: GLL over the graph, driven by the RSM
    ("ucfs", U + "parser/IGll.kt", "parse", "m"),
    ("ucfs", U + "parser/IGll.kt", "initDescriptors", "m"),
    ("ucfs", U + "parser/IGll.kt", "handleNonterminalEdge", "m"),
    ("ucfs", U + "parser/IGll.kt", "handleTerminalEdge", "m"),
    ("ucfs", U + "parser/Gll.kt", "handleDescriptor", "m"),
    ("ucfs", U + "parser/Gll.kt", "handleTerminalRsmState", "m"),
    ("ucfs", U + "parser/Gll.kt", "isParseResult", "m"),
    ("ucfs", U + "intersection/IntersectionEngine.kt", "handleEdges", "m"),
    ("ucfs", U + "gss/GraphStructuredStack.kt", "addEdge", "m"),
    ("ucfs", U + "gss/GraphStructuredStack.kt", "pop", "m"),
    ("ucfs", U + "descriptors/DescriptorsStorage.kt", "add", "m"),
    ("ucfs", U + "sppf/SppfStorage.kt", "addNonterminalNode", "m"),
    ("ucfs", U + "sppf/SppfStorage.kt", "addIntermediateNode", "m"),
    # Qilin side: export, grammar, solve; the PAG sources behind the decisions
    ("qilin", None, "PagExport", "t"),
    ("qilin", None, "PointsToGrammar", "t"),
    ("qilin", None, "UcfsPointsTo", "t"),
    ("qilin", C + "builder/CallGraphBuilder.java", "addVirtualEdge", "m"),
    ("qilin", C + "builder/ExceptionHandler.java", "dispatch", "m"),
    ("qilin", C + "solver/Solver.java", "handleStoreEdge", "m"),
    ("qilin", "qilin.core/src/qilin/util/PTAUtils.java", "addWithTypeFiltering", "m"),
    ("qilin", C + "sets/HybridPointsToSet.java", "add", "m"),
]

HEADINGS = [
    "## 1. Экспорт PAG в граф UCFS",
    "## 2. Грамматика points-to",
    "## 3. Почему GLL работает на разных грамматиках",
    "## 4. Проверка: один решатель и один экспорт на разных грамматиках",
    "## 5. Расхождения со Spark",
    "## 6. Ограничения",
]

REQUIRED_KEYS = ["Scott2010Gll", "Abzalov2026Gll", "Sridharan2005Demand", "Alur2005Analysis",
                 "Grigorev2017Context", "Scott2013Gll", "Afroozeh2015Faster",
                 "Melski2000Interconvertibility"]

MENTIONS = ["E3PagExportTest", "E3GrammarTest", "E3UcfsPointsToTest", "E3ReceiverAssignTest",
            "otherGrammarsAgainstReference", "pointsToRandomGraphsWithBars", "ucfsTeamGrammarGivesReversedPairs",
            "allProgramsAgainstReferences", "callGraphBindingAllPrograms", "ReceiverBinding.CALL_GRAPH",
            "bash acceptance/E3/S3_ucfs_pointsto.sh", "bash acceptance/E3/S2_points_to_grammar.sh",
            "bash acceptance/E3/S3b_receiver_assign.sh", "acceptance/E3/probe_scale.sh",
            "R1", "R2", "R3", "R4", "R4b", "R5", "ROOT"]
# mentions required in sections 5 and 6 (from the heading of section 5 to the end of the document)
SECTION56 = ["derivedNew", "derivedNewIntoThis", "derivedNewException", "pairsWithoutDerivedNew", "growthR3",
             "extraR1", "extraR2", "extraR4b"]
PERCENT = re.compile(r"\d+(?:[.,]\d+)?\s?%")

UNIVERSAL = re.compile(
    r"(?<![\w-])(only|never|always|all|any|every|each|none|exactly|guarantee\w*|entire\w*|whole|completely|"
    r"fully|nowhere|только|никогда|всегда|все|всё|всех|всем|всеми|весь|вся|всего|всю|всей|всему|всяк\w*|"
    r"кажд\w*|любой|любая|любое|любые|любых|любого|любом|любому|никакой|никакие|никаких|никакого|"
    r"ни\s+один|ни\s+одна|ни\s+одного|ни\s+разу|нигде|единственн\w*|гарантир\w*|точн\w*|ровно|"
    r"полностью|целиком|заведомо|без\s+исключени\w*)(?![\w-])", re.IGNORECASE)
INTERP = re.compile(r"интерпретация", re.IGNORECASE)
VERIFIED = re.compile(r"проверено:\s*(`[^`]+`|(?:ucfs:)?(?:[\w.-]+/)*[\w.-]+\.(?:kt|java|gradle|py|sh|kts):\d+(?:-\d+)?#\w+)",
                      re.IGNORECASE)
# sentences: split after . ! ? before an upper-case letter, a code span or a bracket (a table row
# is split the same way, so the reference cell and the role cell of one row stay together)
SENTENCE = re.compile(r"(?<=[.!?])\s+(?=[A-ZА-ЯЁ`(«\"])")
BIBLIKE = re.compile(r"(?<![\w/.])([A-Z][A-Za-z]+(?:19|20)\d\d[A-Z][A-Za-z]*)(?![\w/])")
REF = re.compile(r"(?<![\w/.-])(ucfs:)?((?:[\w.-]+/)*[\w.-]+\.(?:kt|java|gradle|py|sh|kts)):(\d+)(?:-(\d+))?#(\w+)")
BARE = re.compile(r"(?<![\w/.-])(?:ucfs:)?(?:[\w.-]+/)*[\w.-]+\.(?:kt|java|gradle|py|sh|kts):\d+(?:-\d+)?(?!\d|-\d|#)")

fails = []


def fail(msg):
    fails.append(msg)
    print("FAIL: " + msg)


def ok(msg):
    print("PASS: " + msg)


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True)
    return r.returncode, r.stdout


def show(repo, commit, path, cache={}):
    key = (repo, commit, path)
    if key not in cache:
        rc, out = git(repo, "show", "%s:%s" % (commit, path))
        cache[key] = out.split("\n") if rc == 0 else None
    return cache[key]


def words(text):
    text = re.sub(r"`[^`]*`", " ", text)
    return len(re.findall(r"[A-Za-zА-Яа-яЁё]{2,}", text))


def code_part(line, path):
    """The line without comments: KDoc/Javadoc lines and // or /* */ parts (Kotlin, Java, Gradle),
    # parts (Python, shell)."""
    t = line.strip()
    if path.endswith((".py", ".sh")):
        return re.sub(r"#.*$", "", line)
    if t.startswith(("*", "/*", "//")):
        return ""
    return re.sub(r"//.*$", "", re.sub(r"/\*.*?\*/", "", line))


def is_declaration(lines, sym, kind, path):
    for ln in lines:
        if kind == "t":
            if re.search(r"\b(class|object|interface|enum|record)\s+%s\b" % re.escape(sym), ln):
                return True
        elif path.endswith(".kt"):
            if re.search(r"\bfun\s+(<[^>]*>\s*)?([\w<>?, ]+\.)?%s\s*\(" % re.escape(sym), ln):
                return True
        else:
            if re.search(r"\b(public|private|protected|static|final|abstract|synchronized|void|boolean|int|long|[A-Z]\w*(<[^>]*>)?)\s+%s\s*\(" % re.escape(sym), ln) \
                    and not re.search(r"(=|return|new)\s*[\w.]*%s\s*\(" % re.escape(sym), ln):
                return True
    return False


def main():
    doc_path, excerpts_path = sys.argv[1], sys.argv[2]
    text = open(doc_path, encoding="utf-8").read().split("\n")

    head = "\n".join(text[:15])
    m = re.search(r"^pin:\s*([0-9a-f]{40})\s*$", head, re.M)
    mu = re.search(r"^ucfs-pin:\s*([0-9a-f]{40})\s*$", head, re.M)
    if not m:
        fail("no line 'pin: <40-hex sha>' in the first 15 lines")
        return
    if not mu:
        fail("no line 'ucfs-pin: <40-hex sha>' in the first 15 lines")
        return
    pin, upin = m.group(1), mu.group(1)
    if git(ROOT, "merge-base", "--is-ancestor", pin, "HEAD")[0] != 0:
        fail("pin %s is not an ancestor of HEAD" % pin)
    if git(ROOT, "merge-base", "--is-ancestor", E3_BASE, pin)[0] != 0:
        fail("pin %s does not descend from the E3 base %s" % (pin, E3_BASE))
    rc, ls = git(ROOT, "grep", "-l", "-E", r"^\s*(object|class) (PagExport|PointsToGrammar|UcfsPointsTo)\b", pin, "--", "qilin.ucfs/src/main")
    found = {n for n in ("PagExport", "PointsToGrammar", "UcfsPointsTo")
             if git(ROOT, "grep", "-q", "-E", r"^\s*(object|class) %s\b" % n, pin, "--", "qilin.ucfs/src/main")[0] == 0}
    if found == {"PagExport", "PointsToGrammar", "UcfsPointsTo"}:
        ok("pin %s holds PagExport, PointsToGrammar, UcfsPointsTo" % pin[:10])
    else:
        fail("pin %s lacks %s in qilin.ucfs/src/main" % (pin[:10], sorted({"PagExport", "PointsToGrammar", "UcfsPointsTo"} - found)))
    props = open(os.path.join(ROOT, "gradle.properties")).read()
    mc = re.search(r"^ucfsCommit=([0-9a-f]{40})\s*$", props, re.M)
    if not mc or mc.group(1) != upin:
        fail("ucfs-pin %s != ucfsCommit of gradle.properties (%s)" % (upin, mc.group(1) if mc else None))
    elif git(UCFS_SRC, "cat-file", "-e", upin + "^{commit}")[0] != 0:
        fail("ucfs-pin %s is not in %s (run scripts/ucfs/bootstrap.sh)" % (upin, UCFS_SRC))
    else:
        ok("ucfs-pin = ucfsCommit = %s, present in .ucfs/src" % upin[:10])

    # headings in order
    pos = []
    for h in HEADINGS:
        idx = [i for i, l in enumerate(text) if l.strip() == h]
        if not idx:
            fail("missing heading '%s'" % h)
        else:
            pos.append(idx[0])
    if len(pos) == len(HEADINGS) and pos == sorted(pos):
        ok("%d mandatory headings in order" % len(HEADINGS))
    elif len(pos) == len(HEADINGS):
        fail("mandatory headings out of order")

    in_code = False
    refs = []          # (lineno, repo, path, a, b, sym, line)
    bare = 0
    sweep_bad = []
    claims = []        # (lineno, sentence) carrying a mark
    cited = set()
    allowed = set(open(os.path.join(ROOT, "acceptance", "E3", "bib_keys.txt")).read().split())
    unknown = set()
    for i, line in enumerate(text, 1):
        if line.strip().startswith("```"):
            in_code = not in_code
            continue
        if in_code:
            continue
        line_refs = list(REF.finditer(line))
        for r in line_refs:
            repo = "ucfs" if r.group(1) else "qilin"
            a = int(r.group(3))
            b = int(r.group(4)) if r.group(4) else a
            refs.append((i, repo, r.group(2), a, b, r.group(5), line))
        for bm in BARE.finditer(line):
            bare += 1
            fail("line %d: reference without '#<symbol>': %s" % (i, bm.group(0)))
        keys_here = set()
        for km in BIBLIKE.finditer(line):
            k = km.group(1)
            keys_here.add(k)
            if k in allowed:
                cited.add(k)
            else:
                unknown.add(k)
        if line_refs and words(REF.sub(" ", line)) < 8:
            fail("line %d: a line with a code reference needs >= 8 words of prose: %s" % (i, line.strip()[:120]))
        if not line.lstrip().startswith("#"):
            for seg in SENTENCE.split(line):
                marked = INTERP.search(seg) or VERIFIED.search(seg)
                if marked:
                    claims.append((i, seg.strip()))
                if UNIVERSAL.search(re.sub(r"`[^`]*`", " ", seg)) and not (
                        REF.search(seg) or any(k in allowed for k in BIBLIKE.findall(seg)) or marked):
                    sweep_bad.append(i)
                    fail("line %d: universal claim without a code reference, bib key or mark (интерпретация, "
                         "проверено: <ref|`command`>) in the same sentence: %s" % (i, seg.strip()[:140]))
    if unknown:
        fail("bib-like keys not in references.bib: %s" % sorted(unknown))
    else:
        ok("every bib-like key is a key of references.bib (%d cited)" % len(cited))
    missing_keys = [k for k in REQUIRED_KEYS if k not in cited]
    if missing_keys:
        fail("required bib keys not cited: %s" % missing_keys)
    else:
        ok("required bib keys cited: %s" % ", ".join(REQUIRED_KEYS))
    if not sweep_bad:
        ok("claim sweep: every universal claim carries a reference, a bib key or a mark")
    body = "\n".join(text)
    for mtn in MENTIONS:
        if not re.search(r"(?<![\w])%s(?![\w])" % re.escape(mtn), body):
            fail("mandatory mention missing: %s" % mtn)
    if re.search("интерпретация", body, re.IGNORECASE):
        ok("the mark 'интерпретация' is used")
    else:
        fail("no section or claim is marked 'интерпретация'")
    s5 = [i for i, l in enumerate(text) if l.strip() == HEADINGS[4]]
    tail = "\n".join(text[s5[0]:]) if s5 else ""
    for mtn in SECTION56:
        if not re.search(r"(?<![\w])%s(?![\w])" % re.escape(mtn), tail):
            fail("sections 5-6 must mention %s" % mtn)
    share = [seg for l in text[s5[0]:] for seg in SENTENCE.split(l)
             if "pairsWithoutDerivedNew" in seg and PERCENT.search(seg)] if s5 else []
    if share:
        ok("sections 5-6 state the share of the answer without the solver-made new edges: %s" % share[0].strip()[:120])
    else:
        fail("sections 5-6 need a sentence with pairsWithoutDerivedNew and a share in percent (E3.md B1)")

    # reference existence
    valid = []
    for (i, repo, path, a, b, sym, line) in refs:
        src = show(UCFS_SRC, upin, path) if repo == "ucfs" else show(ROOT, pin, path)
        where = ("ucfs:" if repo == "ucfs" else "") + "%s:%d%s#%s" % (path, a, "-%d" % b if b != a else "", sym)
        if src is None:
            fail("line %d: %s: file not at the pinned commit" % (i, where))
            continue
        if not (1 <= a <= b <= len(src)) or b - a > 60:
            fail("line %d: %s: line range outside the file or longer than 61 lines" % (i, where))
            continue
        chunk = src[a - 1:b]
        if not any(re.search(r"(?<![\w])%s(?![\w])" % re.escape(sym), code_part(l, path)) for l in chunk):
            fail("line %d: %s: symbol not in code on the referenced lines (comments do not count)" % (i, where))
            continue
        valid.append((i, repo, path, a, b, sym, line, chunk))
    if refs and len(valid) == len(refs):
        ok("%d code references valid at the pins (%d UCFS, %d Qilin)" % (
            len(refs), sum(1 for r in refs if r[1] == "ucfs"), sum(1 for r in refs if r[1] == "qilin")))
    elif not refs:
        fail("no code references")

    # mandatory anchors: own table row, one reference, >= 8 words, declaration
    anchor_lines = set()
    for (repo, path, sym, kind) in REQUIRED:
        cands = [v for v in valid if v[1] == repo and v[5] == sym and (path is None or v[2] == path)]
        good = None
        for v in cands:
            i, _, p, a, b, _, line, chunk = v
            if not line.lstrip().startswith("|"):
                continue
            if len(REF.findall(line)) != 1:
                continue
            if words(REF.sub(" ", line)) < 8:
                continue
            if not is_declaration(chunk, sym, kind, p):
                continue
            good = v
            break
        name = ("ucfs:" if repo == "ucfs" else "") + (path or "<qilin.ucfs>") + "#" + sym
        if good:
            anchor_lines.add(good[0])
            ok("anchor %s: table row %d, declaration at %s:%d" % (name, good[0], good[2], good[3]))
        else:
            fail("anchor %s: needs its own table row with exactly this reference, >= 8 words and the "
                 "declaration in the range (candidates: %s)" % (name, [(c[0], c[3]) for c in cands]))

    with open(excerpts_path, "w", encoding="utf-8") as out:
        out.write("# Excerpts of every reference of %s (Qilin pin %s, UCFS pin %s)\n\n" % (doc_path, pin, upin))
        for (i, repo, path, a, b, sym, line, chunk) in valid:
            out.write("## doc line %d -> %s%s:%d-%d#%s\n\n> %s\n\n```\n" % (
                i, "ucfs:" if repo == "ucfs" else "", path, a, b, sym, line.strip()))
            src = show(UCFS_SRC, upin, path) if repo == "ucfs" else show(ROOT, pin, path)
            lo, hi = max(1, a - 3), min(len(src), b + 3)
            for n in range(lo, hi + 1):
                out.write("%5d  %s\n" % (n, src[n - 1]))
            out.write("```\n\n")
    others = [v for v in valid if v[0] not in anchor_lines]
    for (i, repo, path, a, b, sym, line, chunk) in sorted(others):
        print("JUDGE: doc line %d -> %s%s:%d-%d#%s" % (i, "ucfs:" if repo == "ucfs" else "", path, a, b, sym))
    for (i, seg) in claims:
        print("CLAIM: doc line %d: %s" % (i, seg[:200]))
    print("to judge: %d anchors, %d other references (JUDGE), %d marked claims (CLAIM)" % (
        len(anchor_lines), len(others), len(claims)))
    print("excerpts: %s" % excerpts_path)


if __name__ == "__main__":
    main()
    sys.exit(1 if fails else 0)
