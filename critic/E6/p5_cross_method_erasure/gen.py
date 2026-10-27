"""critic-E6 probe P5: the CS gadgets of E6.md D6 / E6-S4 (loops "by the call sites whose callee reaches
the method of the vertex") at a context-insensitive variable X that is the target of a cross-method
`new` (Solver.handleImplicitCallToFinalizerRegister: object o of method make -> parameter X of another
method mX). Hand-made CI PAG (no Qilin), three methods:
    main:  y = new Y (oy);  d = make() [call site c];  a = d;  a.f = y
    make:  r = new O (o);   return r                    (exit edge r -> d at c)
    mX:    X <- o (cross-method new, X is a jump: stack erased);  w = X.f      (nobody calls mX by a site)
In the language of D6 / E6Reference.CsModel (erasure at X) oy reaches w:
    oy -new-> y -store f-> a ; a <-assign- d <-exit c- r <-new- o  (B phase: the exit is entered: push c)
    o -new-> X (erase: stack := empty) -load f-> w
so (START oy, END w) must be in any sound over-approximation. Variant SPEC builds the loops exactly as
E6-S4 says (method of the vertex: mX for F_IN(X)/B(X), mX for END(w)), variant FIX adds to the loops of
X the sites that reach the method of the object of the cross-method edge (make). Writes
<out>/{SPEC,FIX}/{graph.dot,vertices.tsv}. Usage: python3 -I gen.py <out-dir>"""
import os, sys

out = sys.argv[1]
c = 0  # the only call site
reach = {"main": set(), "make": {c}, "mX": set()}   # sites whose callee reaches the method (CG: main -c-> make)
method = {"y": "main", "d": "main", "a": "main", "r": "make", "w": "mX", "X": "mX", "oy": "main", "o": "make"}

def build(variant):
    vid, verts, E = {}, [], []
    def V(layer, node):
        k = (layer, node)
        if k not in vid:
            vid[k] = len(verts); verts.append(k)
        return vid[k]
    def e(a, l, b):
        E.append((a, l, b))
    jumps = {"X"}
    fin = lambda v: V("F_IN", v) if v in jumps else V("F", v)    # an edge into v (layer F)
    bin_ = lambda v: V("B_IN", v) if v in jumps else V("B", v)   # an edge into v (layer B)
    for o in ("oy", "o"):
        e(V("START", o), "normal", V("OBJ", o))
        for s in reach[method[o]]:
            e(V("START", o), "op--%d" % s, V("START", o))
    for o, v in (("oy", "y"), ("o", "r"), ("o", "X")):           # new
        e(V("OBJ", o), "normal", fin(v)); e(V("B", v), "normal", V("OBJ", o))
    for u, v in (("d", "a"),):                                    # assign u -> v
        e(V("F", u), "normal", fin(v)); e(V("B", v), "normal", bin_(u))
    e(V("F", "r"), "cp--%d" % c, fin("d")); e(V("B", "d"), "op--%d" % c, bin_("r"))   # exit at c
    e(V("F", "y"), "ob--0", bin_("a")); e(V("F", "a"), "cb--0r", bin_("y"))             # a.f = y
    e(V("F", "X"), "cb--0", fin("w")); e(V("B", "w"), "ob--0r", bin_("X"))             # w = X.f
    for v in ("y", "d", "a", "r", "w"):                                                # END gadgets
        e(V("F", v), "normal", V("END", v))
        for s in reach[method[v]]:
            e(V("END", v), "cp--%d" % s, V("END", v))
    for x in jumps:                                                                    # erasure gadgets
        e(V("F_IN", x), "normal", V("F", x)); e(V("B_IN", x), "normal", V("B", x))
        loops = set(reach[method[x]])
        if variant == "FIX":
            loops |= reach["make"]   # the method of the object o of the cross-method edge o -> X
        for s in sorted(loops):
            for L in ("F_IN", "B_IN"):
                e(V(L, x), "cp--%d" % s, V(L, x))
            for L in ("F", "B"):
                e(V(L, x), "op--%d" % s, V(L, x))
    d = os.path.join(out, variant); os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "graph.dot"), "w") as fh:
        fh.write("digraph G {\n" + "".join('%d->%d[label="%s"];\n' % (a, b, l) for a, l, b in E) + "}\n")
    with open(os.path.join(d, "vertices.tsv"), "w") as fh:
        fh.write("".join("%d\t%s\t%s:%s\t%s\n" % (i, L, L, n, n) for i, (L, n) in enumerate(verts)))

for v in ("SPEC", "FIX"):
    build(v)
