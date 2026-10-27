"""critic-E6 probe P2: a small graph with S call-site parenthesis ids and F field bracket ids (as many
ids as the luindex / antlr BALANCED exports of E6.md D10), to see whether the StackOverflowError while
cfl-idr builds its RSM depends on the thread stack size (-Xss) only. Per site c: a -op--c-> p -normal->
r -cp--c-> d (4 vertices); per field i: x -ob--i-> y -cb--i-> z; every d and z -normal-> hub vertex 0, so
the graph is one (weakly) connected component: cfl-idr builds one grammar per component
(Approximation.kt getUnderApprox: splitIntoConnectedComponents) with the ids that occur in it.
Usage: python3 -I gen.py S F out.dot"""
import sys
S, F, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
n = 1  # vertex 0 = hub
with open(out, "w") as fh:
    fh.write("digraph G {\n")
    for c in range(S):
        a, p, r, d = n, n + 1, n + 2, n + 3; n += 4
        fh.write('%d->%d[label="op--%d"];\n%d->%d[label="normal"];\n%d->%d[label="cp--%d"];\n' % (a, p, c, p, r, r, d, c))
        fh.write('%d->0[label="normal"];\n' % d)
    for i in range(F):
        x, y, z = n, n + 1, n + 2; n += 3
        fh.write('%d->%d[label="ob--%d"];\n%d->%d[label="cb--%d"];\n' % (x, y, i, y, z, i))
        fh.write('%d->0[label="normal"];\n' % z)
    fh.write("}\n")
