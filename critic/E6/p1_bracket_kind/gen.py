"""critic-E6 probe P1: the D4 field encoding (E6.md D4) vs mutant M1 (load-bar/store-bar brackets of the
same kind as store/load) on the PAG of qilin.microben.core.array.ArrayElemTypeFiltering (first half,
hand-written CI PAG):  array = new G[10]; g = new G; h = new H; array[0] = g; array[1] = h; i = array[0].
Writes <out>/{D4,M1}/{graph.dot,vertices.tsv} in the -cflidr dump format of E6-S5 and
<out>/andersen.tsv (field-sensitive Andersen of the same PAG, computed here, "var<TAB>obj").
Usage: python3 -I gen.py <out-dir>"""
import os, sys

out = sys.argv[1]
objs = ["oArr", "oG", "oH"]
vars_ = ["array", "g", "h", "i"]
new = [("oArr", "array"), ("oG", "g"), ("oH", "h")]
assign = []
store = [("g", "array", 0), ("h", "array", 0)]   # (y, x, f): x.f = y ; ArrayElement = field 0
load = [("array", 0, "i")]                       # (x, f, z): z = x.f

# Andersen
pt = {v: set() for v in vars_}
heap = {}
for o, v in new:
    pt[v].add(o)
ch = True
while ch:
    ch = False
    for u, v in assign:
        if not pt[u] <= pt[v]:
            pt[v] |= pt[u]; ch = True
    for y, x, f in store:
        for b in pt[x]:
            s = heap.setdefault((b, f), set())
            if not pt[y] <= s:
                s |= pt[y]; ch = True
    for x, f, z in load:
        for b in pt[x]:
            s = heap.get((b, f), set())
            if not s <= pt[z]:
                pt[z] |= s; ch = True
os.makedirs(out, exist_ok=True)
with open(os.path.join(out, "andersen.tsv"), "w") as fh:
    for v in vars_:
        for o in sorted(pt[v]):
            fh.write("%s\t%s\n" % (v, o))

def dump(name, rsuffix):
    vid = {}
    verts = []
    def V(layer, node):
        k = (layer, node)
        if k not in vid:
            vid[k] = len(verts); verts.append(k)
        return vid[k]
    E = []
    for o in objs:
        V("OBJ", o)
    for v in vars_:
        V("F", v); V("B", v)
    for o, v in new:
        E.append((V("OBJ", o), "normal", V("F", v))); E.append((V("B", v), "normal", V("OBJ", o)))
    for u, v in assign:
        E.append((V("F", u), "normal", V("F", v))); E.append((V("B", v), "normal", V("B", u)))
    for y, x, f in store:
        E.append((V("F", y), "ob--%d" % f, V("B", x)))
        E.append((V("F", x), "cb--%d%s" % (f, rsuffix), V("B", y)))
    for x, f, z in load:
        E.append((V("F", x), "cb--%d" % f, V("F", z)))
        E.append((V("B", z), "ob--%d%s" % (f, rsuffix), V("B", x)))
    d = os.path.join(out, name)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "graph.dot"), "w") as fh:
        fh.write("digraph G {\n")
        for a, l, b in E:
            fh.write('%d->%d[label="%s"];\n' % (a, b, l))
        fh.write("}\n")
    with open(os.path.join(d, "vertices.tsv"), "w") as fh:
        for i, (layer, node) in enumerate(verts):
            fh.write("%d\t%s\t%s:%s\t%s\n" % (i, layer, layer, node, node))

dump("D4", "r")   # E6.md D4: load-bar/store-bar are brackets of kind "ir"
dump("M1", "")    # mutant M1: same kind as store/load
