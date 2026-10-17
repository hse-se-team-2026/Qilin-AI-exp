#!/usr/bin/env bash
# E2-S1 acceptance: the map of the Qilin core (docs/ucfs-integration/qilin-core-map.md) exists,
# is committed, and every code reference in it is real.
#
# Reference format (the only accepted one for code):  `<repo path>:<line>#<symbol>`  or
# `<repo path>:<from>-<to>#<symbol>`, e.g. `qilin.core/src/qilin/core/solver/Solver.java:89#propagate`.
# A reference is valid when, at the pinned commit (line `pin: <40-hex sha>` in the first 15
# lines of the map; the pin must be an ancestor of HEAD), the file exists, the line (range) is
# inside the file and <symbol> occurs as a whole word on that line (in that range).
# References are checked against the pin, not the working tree, so later epics cannot make
# them rot. Any `<file>.(java|kt|gradle|py):<n>` mention without `#<symbol>` is a FAIL.
#
# Usage: [MAP=<path>] bash acceptance/E2/S1_core_map.sh          (exit 0 = PASS)
source "$(dirname "$0")/lib.sh"

MAP="${MAP:-docs/ucfs-integration/qilin-core-map.md}"

[ -f "$MAP" ] || { fail "$MAP does not exist"; finish S1_core_map; }
git ls-files --error-unmatch "$MAP" >/dev/null 2>&1 && git diff --quiet HEAD -- "$MAP" \
    && pass "$MAP is committed (no uncommitted edits)" || fail "$MAP is not committed or has uncommitted edits"

python3 - "$MAP" <<'PY' || FAILS=$((FAILS + 1))
import re, subprocess, sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
lines = text.splitlines()
bad = []

def ok(msg): print("PASS: " + msg)
def ko(msg): print("FAIL: " + msg); bad.append(msg)
def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)

# --- pin ---------------------------------------------------------------------------------------
pin = None
for l in lines[:15]:
    m = re.fullmatch(r"\s*[-*]?\s*`?pin:\s*([0-9a-f]{40})`?\s*", l)
    if m:
        pin = m.group(1)
if not pin:
    ko("no line 'pin: <40-hex sha>' in the first 15 lines")
    sys.exit(1)
if git("cat-file", "-e", pin + "^{commit}").returncode != 0:
    ko(f"pin {pin} is not a commit of this repository"); sys.exit(1)
if git("merge-base", "--is-ancestor", pin, "HEAD").returncode != 0:
    ko(f"pin {pin[:12]} is not an ancestor of HEAD"); sys.exit(1)
ok(f"pin {pin[:12]} is an ancestor of HEAD")

# --- references --------------------------------------------------------------------------------
REF = re.compile(r"`([A-Za-z0-9_][A-Za-z0-9_./-]*\.[A-Za-z0-9]+):(\d+)(?:-(\d+))?#([A-Za-z_][A-Za-z0-9_]*)`")
LOOSE = re.compile(r"[A-Za-z0-9_./-]+\.(?:java|kt|kts|gradle|py):\d+(?:-\d+)?(?!\d|-\d|#)")
files_cache = {}

def file_at_pin(p):
    if p not in files_cache:
        r = git("show", f"{pin}:{p}")
        files_cache[p] = r.stdout.splitlines() if r.returncode == 0 else None
    return files_cache[p]

valid = []
for m in REF.finditer(text):
    p, a, b, sym = m.group(1), int(m.group(2)), m.group(3), m.group(4)
    b = int(b) if b else a
    src = file_at_pin(p)
    where = f"`{m.group(0)[1:-1]}`"
    if src is None:
        ko(f"{where}: file does not exist at pin"); continue
    if not (1 <= a <= b <= len(src)) or b - a > 60:
        ko(f"{where}: line range outside the file ({len(src)} lines) or longer than 61 lines"); continue
    if len(sym) < 3:
        ko(f"{where}: symbol shorter than 3 characters"); continue
    if not any(re.search(r"(?<![A-Za-z0-9_])" + re.escape(sym) + r"(?![A-Za-z0-9_])", src[i - 1]) for i in range(a, b + 1)):
        ko(f"{where}: symbol '{sym}' is not on line(s) {a}-{b} at pin"); continue
    valid.append((p, a, b, sym))

stripped = REF.sub("", text)
loose = sorted(set(LOOSE.findall(stripped)))
if loose:
    ko(f"{len(loose)} code reference(s) without '#<symbol>' (not checkable): {loose[:8]}")

distinct = {(p, a, b, s) for p, a, b, s in valid}
nfiles = len({p for p, _, _, _ in valid})
print(f"  references: {len(valid)} valid ({len(distinct)} distinct) in {nfiles} files")
if len(distinct) >= 30 and nfiles >= 12:
    ok(">= 30 distinct valid references in >= 12 files")
else:
    ko(f"need >= 30 distinct valid references in >= 12 files, have {len(distinct)} in {nfiles}")

# --- mandatory anchors: (file path suffix, symbol) --------------------------------------------
REQUIRED = [
    # PAG: graph, edge kinds, per-method PAG and its builder
    ("qilin.core/src/qilin/core/pag/PAG.java", "addEdge"),
    ("qilin.core/src/qilin/core/pag/PAG.java", "getAlloc"),
    ("qilin.core/src/qilin/core/pag/PAG.java", "getSimple"),
    ("qilin.core/src/qilin/core/pag/PAG.java", "getLoad"),
    ("qilin.core/src/qilin/core/pag/PAG.java", "getStoreInv"),
    ("qilin.core/src/qilin/core/pag/PAG.java", "getMethodPAG"),
    ("qilin.core/src/qilin/core/pag/MethodPAG.java", "getInternalReader"),
    ("qilin.core/src/qilin/core/pag/MethodPAG.java", "getInvokeStmts"),
    ("qilin.core/src/qilin/core/builder/MethodNodeFactory.java", "handleStmt"),
    # solver (layer 4)
    ("qilin.core/src/qilin/core/solver/Propagator.java", "propagate"),
    ("qilin.core/src/qilin/core/solver/Solver.java", "propagate"),
    ("qilin.core/src/qilin/core/solver/Solver.java", "processStmts"),
    ("qilin.core/src/qilin/core/solver/Solver.java", "addToPAG"),
    ("qilin.core/src/qilin/core/solver/Solver.java", "handleStoreAndLoadOnBase"),
    ("qilin.core/src/qilin/core/solver/Solver.java", "activateConstraints"),
    ("qilin.core/src/qilin/core/solver/Solver.java", "propagatePTS"),
    ("qilin.core/src/qilin/util/PTAUtils.java", "addWithTypeFiltering"),
    # kernel (layer 3): context parameters, on-the-fly call graph, exceptions
    ("qilin.core/src/qilin/core/CorePTA.java", "parameterize"),
    ("qilin.core/src/qilin/core/builder/CallGraphBuilder.java", "initReachableMethods"),
    ("qilin.core/src/qilin/core/builder/CallGraphBuilder.java", "virtualCallDispatch"),
    ("qilin.core/src/qilin/core/builder/CallGraphBuilder.java", "processCallAssign"),
    ("qilin.core/src/qilin/core/builder/ExceptionHandler.java", "exceptionDispatch"),
    # analysis objects, results and the solver hook
    ("qilin.core/src/qilin/core/PTA.java", "pureRun"),
    ("qilin.core/src/qilin/core/PTA.java", "getNakedReachableMethods"),
    ("qilin.core/src/qilin/core/PTA.java", "getCallGraph"),
    ("qilin.pta/src/qilin/pta/tools/BasePTA.java", "getPropagator"),
    ("qilin.pta/src/qilin/pta/tools/StagedPTA.java", "preAnalysis"),
    # CLI -> Soot -> choice of analysis by -pta=
    ("qilin.pta/src/driver/Main.java", "setupSoot"),
    ("qilin.pta/src/driver/PTAOption.java", "pointstoanalysis"),
    ("qilin.pta/src/driver/PTAPattern.java", "Approach"),
    ("qilin.pta/src/driver/PTAFactory.java", "createPTA"),
]
have = {(p, s) for p, _, _, s in valid}
missing = [f"{p}#{s}" for p, s in REQUIRED if (p, s) not in have]
if missing:
    ko(f"{len(missing)} mandatory anchor(s) missing: {missing}")
else:
    ok(f"all {len(REQUIRED)} mandatory anchors are referenced")

# --- mandatory sections and statements ---------------------------------------------------------
heads = [l for l in lines if re.match(r"#{1,4}\s", l)]
SECTIONS = {
    "PAG": r"PAG",
    "solver": r"[Рр]ешател|Solver",
    "kernel (Ядро)": r"Ядр",
    "choice of analysis (-pta)": r"-pta",
    "integration points": r"[Вв]стра",
    "module qilin.ucfs": r"qilin\.ucfs",
}
for name, rx in SECTIONS.items():
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

sys.exit(1 if bad else 0)
PY

finish S1_core_map
