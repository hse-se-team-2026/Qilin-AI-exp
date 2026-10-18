#!/usr/bin/env python3
"""Checker of the Qilin core map docs/ucfs-integration/qilin-core-map.md (E2-S1a, E2-S1b).

Usage: python3 acceptance/E2/core_map_check.py <a|full> <map.md> <excerpts-out.md>
Exit 0 = all checks pass, 1 = some check failed.

Reference format (the only accepted one for code): `<repo path>:<line>#<symbol>` or
`<repo path>:<from>-<to>#<symbol>` (range <= 61 lines). A reference is valid when, at the pinned
commit (line `pin: <40-hex sha>` in the first 15 lines; the pin is a descendant of the E2 base
73db8b4 and an ancestor of HEAD), the file exists, the lines exist and <symbol> occurs on them as
a whole word. References are checked against the pin, not the working tree, so later epics cannot
make them rot. A `<file>.(java|kt|gradle|py):<n>` mention without `#<symbol>` is a FAIL.

On top of existence:
  * every line with a reference carries >= 8 words of prose outside code spans (a role, not a
    bare list of links);
  * every mandatory anchor (REQUIRED) has its own table row (a line starting with '|') that holds
    exactly this one reference and >= 8 words of prose (the anchor's role), and the referenced
    line range holds the DECLARATION of the symbol (method/constructor, class/enum/interface, or
    the option name as a string literal), not a call site;
  * mandatory section headings, a link to docs/QilinArchitecture.png and an explicit
    "интерпретация" mark.
The script also writes <excerpts-out.md>: every reference with its map line and the pinned code
lines, and prints a reproducible sample of 8 non-anchor references (seeded by the pin) for the
verifier's judgment (see docs/ai/tickets/E2-S1a.md / E2-S1b.md).
"""
import random
import re
import subprocess
import sys

E2_BASE = "73db8b4d8edb3d35ab318cb8f4f42a93c9e42f56"

C = "qilin.core/src/qilin/core/"
# (path, symbol, declaration kind) ; kinds: m = method/constructor, t = type, o = option string
REQUIRED_A = [
    # PAG: graph, edge kinds, per-method PAG and its builder, context nodes of the global PAG
    (C + "pag/PAG.java", "addEdge", "m"),
    (C + "pag/PAG.java", "getAlloc", "m"),
    (C + "pag/PAG.java", "getSimple", "m"),
    (C + "pag/PAG.java", "getLoad", "m"),
    (C + "pag/PAG.java", "getStoreInv", "m"),
    (C + "pag/PAG.java", "getMethodPAG", "m"),
    (C + "pag/MethodPAG.java", "getInternalReader", "m"),
    (C + "pag/MethodPAG.java", "getInvokeStmts", "m"),
    (C + "builder/MethodNodeFactory.java", "handleStmt", "m"),
    (C + "pag/ContextVarNode.java", "ContextVarNode", "t"),
    (C + "pag/ContextField.java", "ContextField", "t"),
    # solver (layer 4), including the edges it derives into the global PAG
    (C + "solver/Propagator.java", "propagate", "m"),
    (C + "solver/Solver.java", "propagate", "m"),
    (C + "solver/Solver.java", "processStmts", "m"),
    (C + "solver/Solver.java", "addToPAG", "m"),
    (C + "solver/Solver.java", "handleStoreAndLoadOnBase", "m"),
    (C + "solver/Solver.java", "handleStoreEdge", "m"),
    (C + "solver/Solver.java", "handleLoadEdge", "m"),
    (C + "solver/Solver.java", "activateConstraints", "m"),
    (C + "solver/Solver.java", "propagatePTS", "m"),
    ("qilin.core/src/qilin/util/PTAUtils.java", "addWithTypeFiltering", "m"),
    # kernel (layer 3): context parameters, on-the-fly call graph, exceptions
    (C + "CorePTA.java", "parameterize", "m"),
    (C + "builder/CallGraphBuilder.java", "initReachableMethods", "m"),
    (C + "builder/CallGraphBuilder.java", "virtualCallDispatch", "m"),
    (C + "builder/CallGraphBuilder.java", "addVirtualEdge", "m"),
    (C + "builder/CallGraphBuilder.java", "processCallAssign", "m"),
    (C + "builder/ExceptionHandler.java", "exceptionDispatch", "m"),
]
REQUIRED_B = [
    # analysis objects, results, statistics and the solver hook
    (C + "PTA.java", "pureRun", "m"),
    (C + "PTA.java", "getNakedReachableMethods", "m"),
    (C + "PTA.java", "getCallGraph", "m"),
    ("qilin.core/src/qilin/stat/PAGStat.java", "PAGStat", "t"),
    ("qilin.pta/src/qilin/pta/tools/BasePTA.java", "getPropagator", "m"),
    ("qilin.pta/src/qilin/pta/tools/BasePTA.java", "run", "m"),
    ("qilin.pta/src/qilin/pta/tools/StagedPTA.java", "preAnalysis", "m"),
    # CLI -> Soot -> choice of analysis by -pta
    ("qilin.pta/src/driver/Main.java", "run", "m"),
    ("qilin.pta/src/driver/Main.java", "setupSoot", "m"),
    ("qilin.pta/src/driver/PTAOption.java", "pointstoanalysis", "o"),
    ("qilin.pta/src/driver/PTAOption.java", "parseCommandLine", "m"),
    ("qilin.pta/src/driver/PTAPattern.java", "Approach", "t"),
    ("qilin.pta/src/driver/PTAFactory.java", "createPTA", "m"),
]
SECTIONS_A = {
    "PAG": r"PAG",
    "solver": r"[Рр]ешател|Solver",
    "kernel (Ядро)": r"Ядр",
    "two representations (internal vs global PAG)": r"[Пп]редставлен|[Гг]лобальн",
}
SECTIONS_B = {
    "choice of analysis (-pta)": r"-pta",
    "integration points": r"[Вв]стра",
    "seam (шов)": r"[Шш]ов",
    "module qilin.ucfs": r"qilin\.ucfs",
}
PARTS = {
    # part: (anchors, sections, min distinct refs, min files)
    "a": (REQUIRED_A, SECTIONS_A, 30, 11),
    "full": (REQUIRED_A + REQUIRED_B, {**SECTIONS_A, **SECTIONS_B}, 48, 19),
}
SAMPLE_SIZE = 8
MIN_WORDS = 8

REF = re.compile(r"`([A-Za-z0-9_][A-Za-z0-9_./-]*\.[A-Za-z0-9]+):(\d+)(?:-(\d+))?#([A-Za-z_][A-Za-z0-9_]*)`")
LOOSE = re.compile(r"[A-Za-z0-9_./-]+\.(?:java|kt|kts|gradle|py):\d+(?:-\d+)?(?!\d|-\d|#)")
CODE_SPAN = re.compile(r"`[^`]*`")
WORD = re.compile(r"[A-Za-zА-Яа-яЁё]{2,}")
MODS = r"(?:(?:public|protected|private|static|final|abstract|synchronized|native|default|strictfp)\s+)*"
NOT_DECL_START = re.compile(r"^\s*(?:return|new|throw|else|if|while|for|case)\b")


def is_decl(line, sym, kind):
    s = re.escape(sym)
    if kind == "t":
        return re.search(r"\b(?:class|enum|interface|record)\s+" + s + r"\b", line) is not None
    if kind == "o":
        return re.search(r'"' + s + r'"', line) is not None
    if NOT_DECL_START.search(line):
        return False
    ann = r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    # method: [annotations] [modifiers] [<T>] <return type> sym(
    method = ann + MODS + r"(?:<[^>]+>\s+)?[\w$.]+(?:<[^()=;]*>)?(?:\[\])*\s+" + s + r"\s*\("
    # constructor: [annotations] <at least one modifier> sym(
    ctor = ann + r"(?:(?:public|protected|private)\s+)" + s + r"\s*\("
    return re.search(method, line) is not None or re.search(ctor, line) is not None


def prose_words(line):
    return len(WORD.findall(CODE_SPAN.sub(" ", line).replace("|", " ")))


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def main():
    part, path, excerpts_out = sys.argv[1], sys.argv[2], sys.argv[3]
    anchors, sections, min_refs, min_files = PARTS[part]
    text = open(path, encoding="utf-8").read()
    lines = text.splitlines()
    bad = []

    def ok(msg):
        print("PASS: " + msg)

    def ko(msg):
        print("FAIL: " + msg)
        bad.append(msg)

    # --- pin ---------------------------------------------------------------------------------
    pin = None
    for l in lines[:15]:
        m = re.fullmatch(r"\s*[-*]?\s*`?pin:\s*([0-9a-f]{40})`?\s*", l)
        if m:
            pin = m.group(1)
    if not pin:
        ko("no line 'pin: <40-hex sha>' in the first 15 lines")
        return 1
    if git("cat-file", "-e", pin + "^{commit}").returncode != 0:
        ko(f"pin {pin} is not a commit of this repository")
        return 1
    if git("merge-base", "--is-ancestor", pin, "HEAD").returncode != 0:
        ko(f"pin {pin[:12]} is not an ancestor of HEAD")
        return 1
    if git("merge-base", "--is-ancestor", E2_BASE, pin).returncode != 0:
        ko(f"pin {pin[:12]} is older than the E2 base {E2_BASE[:12]} (must be 73db8b4 or a descendant)")
        return 1
    ok(f"pin {pin[:12]} is an ancestor of HEAD and a descendant of {E2_BASE[:7]}")

    # --- references ------------------------------------------------------------------------
    files_cache = {}

    def file_at_pin(p):
        if p not in files_cache:
            r = git("show", f"{pin}:{p}")
            files_cache[p] = r.stdout.splitlines() if r.returncode == 0 else None
        return files_cache[p]

    valid = {}          # (p, a, b, sym) -> first map line number
    short_lines = []
    for ln, line in enumerate(lines, 1):
        refs = list(REF.finditer(line))
        if not refs:
            continue
        if prose_words(line) < MIN_WORDS:
            short_lines.append(ln)
        for m in refs:
            p, a, b, sym = m.group(1), int(m.group(2)), m.group(3), m.group(4)
            b = int(b) if b else a
            src = file_at_pin(p)
            where = f"line {ln}: `{m.group(0)[1:-1]}`"
            if src is None:
                ko(f"{where}: file does not exist at pin")
                continue
            if not (1 <= a <= b <= len(src)) or b - a > 60:
                ko(f"{where}: line range outside the file ({len(src)} lines) or longer than 61 lines")
                continue
            if len(sym) < 3:
                ko(f"{where}: symbol shorter than 3 characters")
                continue
            word = re.compile(r"(?<![A-Za-z0-9_])" + re.escape(sym) + r"(?![A-Za-z0-9_])")
            if not any(word.search(src[i - 1]) for i in range(a, b + 1)):
                ko(f"{where}: symbol '{sym}' is not on line(s) {a}-{b} at pin")
                continue
            valid.setdefault((p, a, b, sym), ln)

    loose = sorted(set(LOOSE.findall(REF.sub("", text))))
    if loose:
        ko(f"{len(loose)} code reference(s) without '#<symbol>' (not checkable): {loose[:8]}")
    if short_lines:
        ko(f"{len(short_lines)} line(s) with references have < {MIN_WORDS} words of prose "
           f"outside code spans (map lines {short_lines[:10]})")
    else:
        ok(f"every line with a reference has >= {MIN_WORDS} words of prose")

    nfiles = len({k[0] for k in valid})
    print(f"  references: {len(valid)} distinct valid in {nfiles} files")
    if len(valid) >= min_refs and nfiles >= min_files:
        ok(f">= {min_refs} distinct valid references in >= {min_files} files")
    else:
        ko(f"need >= {min_refs} distinct valid references in >= {min_files} files, have {len(valid)} in {nfiles}")

    # --- mandatory anchors: own table row with a role, pointing at the declaration -----------
    anchor_keys = set()
    missing, nodecl, norow = [], [], []
    for p, sym, kind in anchors:
        cands = [k for k in valid if k[0] == p and k[3] == sym]
        if not cands:
            missing.append(f"{p}#{sym}")
            continue
        decl = [k for k in cands
                if any(is_decl(file_at_pin(p)[i - 1], sym, kind) for i in range(k[1], k[2] + 1))]
        if not decl:
            nodecl.append(f"{p.rsplit('/', 1)[-1]}#{sym} ({', '.join(str(k[1]) for k in cands)})")
            continue
        rows = []
        for k in decl:
            for ln, line in enumerate(lines, 1):
                rs = REF.findall(line)
                if line.lstrip().startswith("|") and len(rs) == 1 \
                        and (rs[0][0], int(rs[0][1]), int(rs[0][2] or rs[0][1]), rs[0][3]) == k \
                        and prose_words(line) >= MIN_WORDS:
                    rows.append(ln)
            anchor_keys.add(k)
        if not rows:
            norow.append(f"{p.rsplit('/', 1)[-1]}#{sym}")
    if missing:
        ko(f"{len(missing)} mandatory anchor(s) missing: {missing}")
    if nodecl:
        ko(f"{len(nodecl)} mandatory anchor(s) point at a use, not at the declaration: {nodecl}")
    if norow:
        ko(f"{len(norow)} mandatory anchor(s) have no own table row '| `ref` | role >= {MIN_WORDS} words |': {norow}")
    if not (missing or nodecl or norow):
        ok(f"all {len(anchors)} mandatory anchors: declaration, own table row with a role")

    # --- mandatory sections and statements -----------------------------------------------------
    heads = [l for l in lines if re.match(r"#{1,4}\s", l)]
    for name, rx in sections.items():
        if any(re.search(rx, h) for h in heads):
            ok(f"section heading for {name}")
        else:
            ko(f"no section heading matching /{rx}/ ({name})")
    if "docs/QilinArchitecture.png" in text:
        ok("refers to docs/QilinArchitecture.png (layers of the kernel)")
    else:
        ko("does not refer to docs/QilinArchitecture.png")
    if re.search(r"[Ии]нтерпретаци", text):
        ok("marks interpretations explicitly")
    else:
        ko("no statement marked as 'интерпретация'")

    # --- material for the verifier's judgment ------------------------------------------------
    with open(excerpts_out, "w", encoding="utf-8") as out:
        out.write(f"# Excerpts of {path} at pin {pin}\n\n")
        for k in sorted(valid, key=lambda k: valid[k]):
            p, a, b, sym = k
            src = file_at_pin(p)
            tag = "ANCHOR" if k in anchor_keys else "ref"
            out.write(f"## [{tag}] `{p}:{a}{'-' + str(b) if b != a else ''}#{sym}` (map line {valid[k]})\n")
            out.write(f"map: {lines[valid[k] - 1].strip()}\n```\n")
            for i in range(max(1, a - 2), min(len(src), b + 2) + 1):
                out.write(f"{i:5d}{'>' if a <= i <= b else ' '} {src[i - 1]}\n")
            out.write("```\n\n")
    others = sorted(k for k in valid if k not in anchor_keys)
    sample = random.Random(pin).sample(others, min(SAMPLE_SIZE, len(others)))
    print(f"  excerpts of all {len(valid)} references: {excerpts_out}")
    print(f"  judgment sample ({len(sample)} of {len(others)} non-anchor references, seed = pin):")
    for p, a, b, sym in sample:
        print(f"    SAMPLE `{p}:{a}{'-' + str(b) if b != a else ''}#{sym}`")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
