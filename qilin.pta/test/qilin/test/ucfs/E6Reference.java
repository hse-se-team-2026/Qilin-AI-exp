package qilin.test.ucfs;

import qilin.CoreConfig;
import qilin.core.PTA;
import qilin.core.PointsToAnalysis;
import qilin.core.pag.AllocNode;
import qilin.core.pag.GlobalVarNode;
import qilin.core.pag.LocalVarNode;
import qilin.core.pag.Node;
import qilin.core.pag.PAG;
import qilin.core.pag.Parm;
import qilin.util.Pair;
import soot.Local;
import soot.RefLikeType;
import soot.SootMethod;
import soot.Value;
import soot.jimple.AssignStmt;
import soot.jimple.ClassConstant;
import soot.jimple.InstanceInvokeExpr;
import soot.jimple.InvokeExpr;
import soot.jimple.NullConstant;
import soot.jimple.Stmt;
import soot.jimple.StringConstant;
import soot.jimple.spark.pag.SparkField;
import soot.jimple.toolkits.callgraph.Edge;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * E6 acceptance: references of the IDR export computed by the test from the PAG maps, Soot's call
 * graph and the Jimple of the call sites (docs/ai/tickets/E6.md D4-D8). Not the code under test:
 * it does not use qilin.ucfs.idr, cfl-idr-with-gll or UCFS.
 * <ul>
 *   <li>{@link #fieldsReference}: Andersen (L_FT, E3 {@code E3UcfsPointsToTest.andersen}) over the CI
 *       PAG with the receivers bound along the call graph (E3 REF2) and the exception flow as
 *       assignments throw variable -> handler variable / method throw node (MethodPAG exception
 *       edges) instead of the objects Spark dispatched;</li>
 *   <li>{@link CsModel}: the context-sensitive language of the CS export (Sridharan2006Refinement,
 *       L_F with R_C): calls entered and left per call site, partial balance (returns without a
 *       matching call first, calls never returned from last), the call stack erased at the
 *       context-insensitive variables (globals; targets of cross-method object edges), fields as
 *       balanced brackets of two kinds (store..load, load-bar..store-bar). {@link CsModel#boundedPairs}
 *       enumerates the paths with both stacks at most {@code d} deep: every pair it finds is in the
 *       language, so it must be in any sound over-approximation.</li>
 * </ul>
 */
final class E6Reference {
    private E6Reference() {
    }

    static final String CORE = E3UcfsPointsToTest.P;
    static final String CONTEXT = "qilin.microben.context.";

    /**
     * The 43 small programs of E3 (E3UcfsPointsToTest.PROGRAMS) and the 18 context-sensitivity
     * programs of qilin.microben (context/cfa, obj, hyb, type; context/collections is left out: it
     * runs java.util with bodies). Full class names.
     */
    static List<String> programs() {
        List<String> out = new ArrayList<>();
        for (String p : E3UcfsPointsToTest.PROGRAMS) {
            out.add(CORE + p);
        }
        for (String p : CONTEXT_PROGRAMS) {
            out.add(CONTEXT + p);
        }
        return out;
    }

    static final String[] CONTEXT_PROGRAMS = {
            "cfa.CFA1k0", "cfa.CFA1k1", "cfa.CFA1k2", "cfa.CFA2k",
            "obj.OBJ1k0", "obj.OBJ1k1", "obj.OBJ1k2", "obj.OBJ1k3", "obj.OBJ1k4", "obj.OBJ1k5",
            "obj.OBJ2k0", "obj.OBJ2k1", "obj.OBJ2k2", "hyb.Hyb0", "hyb.Hyb1", "hyb.Hyb2",
            "type.Type1k0", "type.Type2k0",
    };

    static Node ci(Node n) {
        return E3UcfsPointsToTest.ci(n);
    }

    // ------------------------------------------------------------------ call edges per site
    /** One labeled interprocedural edge: from -> to at the call statement site (entry or exit). */
    record CallEdge(Node from, Node to, Stmt site, boolean entry) {
    }

    private static Node valueNode(PAG pag, SootMethod m, Value v) {
        if (v instanceof Local l) {
            return pag.findLocalVarNode(l);
        }
        if (v instanceof StringConstant || v instanceof ClassConstant) {
            return pag.findLocalVarNode(new Pair<>(m, v));
        }
        return null;
    }

    /**
     * The call edges of every call graph edge out of an invoke statement: argument -> parameter and
     * Jimple receiver (base of an instance invoke) -> this of a non-static callee are entries; the
     * callee's return node -> the assigned variable, and with precise exceptions the callee's throw
     * node -> the throw variable of the statement, are exits.
     */
    static List<CallEdge> callEdges(PTA pta) {
        PAG pag = pta.getPag();
        boolean pe = CoreConfig.v().getPtaConfig().preciseExceptions;
        Set<List<Object>> seen = new HashSet<>();
        List<CallEdge> out = new ArrayList<>();
        java.util.function.Consumer<CallEdge> add = ce -> {
            if (ce.from() != null && ce.to() != null
                    && seen.add(List.of(ci(ce.from()), ci(ce.to()), ce.site(), ce.entry()))) {
                out.add(new CallEdge(ci(ce.from()), ci(ce.to()), ce.site(), ce.entry()));
            }
        };
        for (Edge e : pta.getCallGraph()) {
            if (!(e.srcUnit() instanceof Stmt s) || !s.containsInvokeExpr()) {
                continue;
            }
            SootMethod src = e.src();
            SootMethod tgt = e.tgt();
            InvokeExpr ie = s.getInvokeExpr();
            for (int i = 0; i < ie.getArgCount() && i < tgt.getParameterCount(); i++) {
                Value a = ie.getArg(i);
                if (a.getType() instanceof RefLikeType && !(a instanceof NullConstant)
                        && tgt.getParameterType(i) instanceof RefLikeType) {
                    add.accept(new CallEdge(valueNode(pag, src, a), pag.findLocalVarNode(new Parm(tgt, i)), s, true));
                }
            }
            if (ie instanceof InstanceInvokeExpr iie && !tgt.isStatic()) {
                add.accept(new CallEdge(valueNode(pag, src, iie.getBase()),
                        pag.findLocalVarNode(new Parm(tgt, PointsToAnalysis.THIS_NODE)), s, true));
            }
            if (s instanceof AssignStmt as && as.getLeftOp().getType() instanceof RefLikeType
                    && tgt.getReturnType() instanceof RefLikeType) {
                add.accept(new CallEdge(pag.findLocalVarNode(new Parm(tgt, PointsToAnalysis.RETURN_NODE)),
                        valueNode(pag, src, as.getLeftOp()), s, false));
            }
            if (pe) {
                add.accept(new CallEdge(pag.findLocalVarNode(new Parm(tgt, PointsToAnalysis.THROW_NODE)),
                        pag.findLocalVarNode(s), s, false));
            }
        }
        return out;
    }

    /** MethodPAG exception edges (throw variable -> handler variable or method throw node), CI. */
    static List<Node[]> exceptionAssigns(PTA pta) {
        List<Node[]> out = new ArrayList<>();
        for (SootMethod m : pta.getNakedReachableMethods()) {
            if (m.isPhantom()) {
                continue;
            }
            pta.getPag().getMethodPAG(m).getExceptionEdges().forEach((t, ws) -> {
                for (Node w : ws) {
                    out.add(new Node[]{ci(t), ci(w)});
                }
            });
        }
        return out;
    }

    /**
     * The CI PAG of the export: E3's edges without the object edges into {@code this} (except ROOT)
     * and into exception targets, without the copies that the call edges replace; when
     * {@code withCalls}, the call edges are added as plain assignments (the FIELDS export) and the
     * exception assignments are added in both cases.
     */
    static E3UcfsPointsToTest.Edges ciEdges(PTA pta, List<CallEdge> calls, boolean withCalls) {
        AllocNode root = pta.getRootNode().base();
        List<Node[]> exc = exceptionAssigns(pta);
        Set<Node> excTargets = new HashSet<>();
        exc.forEach(e -> excTargets.add(e[1]));
        Set<List<Node>> callPairs = new HashSet<>();
        calls.forEach(c -> callPairs.add(List.of(c.from(), c.to())));
        E3UcfsPointsToTest.Edges base = new E3UcfsPointsToTest.Edges(pta.getPag());
        base.assign.removeIf(e -> callPairs.contains(List.of(e[0], e[1])));
        List<Node[]> extra = new ArrayList<>(exc);
        if (withCalls) {
            calls.forEach(c -> extra.add(new Node[]{c.from(), c.to()}));
        }
        return base.with((o, v) -> (v instanceof LocalVarNode lv && lv.isThis() && !o.equals(root))
                || excTargets.contains(v), extra);
    }

    /** Andersen fixpoint of the FIELDS export (no filters), keyed by CI variables. */
    static Map<Node, Set<AllocNode>> fieldsReference(PTA pta) {
        return E3UcfsPointsToTest.normalize(E3UcfsPointsToTest.andersen(ciEdges(pta, callEdges(pta), true),
                E3UcfsPointsToTest.Filters.NONE, true));
    }

    // ------------------------------------------------------------------ CS language, bounded
    static final class CsModel {
        final Map<Node, List<Node>> allocOut = new HashMap<>();   // o -> v
        final Map<Node, List<Node>> allocIn = new HashMap<>();    // v -> o
        final Map<Node, List<Node>> assignOut = new HashMap<>();
        final Map<Node, List<Node>> assignIn = new HashMap<>();
        final Map<Node, List<Object[]>> callOut = new HashMap<>(); // from -> {to, siteId, entry}
        final Map<Node, List<Object[]>> callIn = new HashMap<>();  // to -> {from, siteId, entry}
        final Map<Node, List<Object[]>> storeBySrc = new HashMap<>();  // y -> {x, f}  (x.f = y)
        final Map<Node, List<Object[]>> storeByBase = new HashMap<>(); // x -> {y, f}
        final Map<Node, List<Object[]>> loadByBase = new HashMap<>();  // x -> {f, z}  (z = x.f)
        final Map<Node, List<Object[]>> loadByDst = new HashMap<>();   // z -> {x, f}
        final Set<Node> jumps = new HashSet<>();
        final List<AllocNode> objects = new ArrayList<>();
        /** Objects whose enumeration in the last {@link #boundedPairs} call stopped at maxStates (r2, critic m2). */
        int truncated;
        private final Map<Object, Integer> ids = new HashMap<>();

        private int id(Object o) {
            return ids.computeIfAbsent(o, k -> ids.size() + 1);
        }

        private static <K, V> void put(Map<K, List<V>> m, K k, V v) {
            m.computeIfAbsent(k, x -> new ArrayList<>()).add(v);
        }

        CsModel(PTA pta) {
            List<CallEdge> calls = callEdges(pta);
            E3UcfsPointsToTest.Edges g = ciEdges(pta, calls, false);
            AllocNode root = pta.getRootNode().base();
            Set<Node> objs = new HashSet<>();
            for (Node[] e : g.alloc) {
                put(allocOut, e[0], e[1]);
                put(allocIn, e[1], e[0]);
                objs.add(e[0]);
                AllocNode o = (AllocNode) e[0];
                if (e[1] instanceof LocalVarNode lv && !o.equals(root) && o.getMethod() != null
                        && !o.getMethod().equals(lv.getMethod())) {
                    jumps.add(e[1]);
                }
                if (e[1] instanceof GlobalVarNode) {
                    jumps.add(e[1]);
                }
            }
            for (Node[] e : g.assign) {
                put(assignOut, e[0], e[1]);
                put(assignIn, e[1], e[0]);
                for (Node n : e) {
                    if (n instanceof GlobalVarNode) {
                        jumps.add(n);
                    }
                }
            }
            for (CallEdge c : calls) {
                int s = id(c.site());
                put(callOut, c.from(), new Object[]{c.to(), s, c.entry()});
                put(callIn, c.to(), new Object[]{c.from(), s, c.entry()});
            }
            for (Object[] st : g.store) { // {y, x, f}
                put(storeBySrc, (Node) st[0], new Object[]{st[1], id(st[2])});
                put(storeByBase, (Node) st[1], new Object[]{st[0], id(st[2])});
            }
            for (Object[] ld : g.load) { // {x, f, z}
                put(loadByBase, (Node) ld[0], new Object[]{id(ld[1]), ld[2]});
                put(loadByDst, (Node) ld[2], new Object[]{ld[0], id(ld[1])});
            }
            objs.forEach(o -> objects.add((AllocNode) o));
        }

        private record St(Node n, int phase, int[] a, int[] b) { // phase 0 = F, 1 = B, 2 = object
            @Override
            public boolean equals(Object o) {
                return o instanceof St s && s.n == n && s.phase == phase && Arrays.equals(s.a, a) && Arrays.equals(s.b, b);
            }

            @Override
            public int hashCode() {
                return (System.identityHashCode(n) * 31 + phase) * 31 + Arrays.hashCode(a) * 17 + Arrays.hashCode(b);
            }
        }

        private static int[] push(int[] s, int x) {
            int[] r = Arrays.copyOf(s, s.length + 1);
            r[s.length] = x;
            return r;
        }

        private static int[] pop(int[] s) {
            return Arrays.copyOf(s, s.length - 1);
        }

        private static final int[] EMPTY = new int[0];

        /**
         * Pairs (variable -> objects) with a path in the CS language whose call stack and field
         * stack stay at most {@code d} deep, and at most {@code maxStates} states per object; the number of
         * objects whose enumeration was cut by maxStates is left in {@link #truncated}.
         * Field stack symbols: +f = store..load bracket, -f = load-bar..store-bar bracket.
         */
        Map<Node, Set<AllocNode>> boundedPairs(int d, int maxStates) {
            Map<Node, Set<AllocNode>> out = new HashMap<>();
            truncated = 0;
            for (AllocNode o : objects) {
                Set<St> seen = new HashSet<>();
                ArrayDeque<St> work = new ArrayDeque<>();
                St s0 = new St(o, 2, EMPTY, EMPTY);
                seen.add(s0);
                work.add(s0);
                while (!work.isEmpty() && seen.size() < maxStates) {
                    St s = work.poll();
                    List<St> next = new ArrayList<>();
                    if (s.phase == 2) {
                        for (Node v : allocOut.getOrDefault(s.n, List.of())) {
                            next.add(new St(v, 0, jumps.contains(v) ? EMPTY : s.a, s.b));
                        }
                    } else if (s.phase == 0) {
                        if (s.b.length == 0) {
                            out.computeIfAbsent(s.n, k -> new HashSet<>()).add(o);
                        }
                        for (Node w : assignOut.getOrDefault(s.n, List.of())) {
                            next.add(new St(w, 0, jumps.contains(w) ? EMPTY : s.a, s.b));
                        }
                        for (Object[] c : callOut.getOrDefault(s.n, List.of())) {
                            Node w = (Node) c[0];
                            int site = (Integer) c[1];
                            int[] a = call(s.a, site, (Boolean) c[2], d);
                            if (a != null) {
                                next.add(new St(w, 0, jumps.contains(w) ? EMPTY : a, s.b));
                            }
                        }
                        if (s.b.length < d) {
                            for (Object[] st : storeBySrc.getOrDefault(s.n, List.of())) {
                                next.add(new St((Node) st[0], 1, s.a, push(s.b, (Integer) st[1])));
                            }
                        }
                        if (s.b.length > 0) {
                            int top = s.b[s.b.length - 1];
                            for (Object[] ld : loadByBase.getOrDefault(s.n, List.of())) {
                                if (top == (Integer) ld[0]) {
                                    Node z = (Node) ld[1];
                                    next.add(new St(z, 0, jumps.contains(z) ? EMPTY : s.a, pop(s.b)));
                                }
                            }
                            for (Object[] st : storeByBase.getOrDefault(s.n, List.of())) {
                                if (top == -(Integer) st[1]) {
                                    Node y = (Node) st[0];
                                    next.add(new St(y, 1, jumps.contains(y) ? EMPTY : s.a, pop(s.b)));
                                }
                            }
                        }
                    } else {
                        for (Node u : assignIn.getOrDefault(s.n, List.of())) {
                            next.add(new St(u, 1, jumps.contains(u) ? EMPTY : s.a, s.b));
                        }
                        for (Object[] c : callIn.getOrDefault(s.n, List.of())) {
                            Node u = (Node) c[0];
                            // backwards: an entry is left (return-like), an exit is entered (call-like)
                            int[] a = call(s.a, (Integer) c[1], !(Boolean) c[2], d);
                            if (a != null) {
                                next.add(new St(u, 1, jumps.contains(u) ? EMPTY : a, s.b));
                            }
                        }
                        if (s.b.length < d) {
                            for (Object[] ld : loadByDst.getOrDefault(s.n, List.of())) {
                                Node x = (Node) ld[0];
                                next.add(new St(x, 1, jumps.contains(x) ? EMPTY : s.a, push(s.b, -(Integer) ld[1])));
                            }
                        }
                        for (Node ob : allocIn.getOrDefault(s.n, List.of())) {
                            next.add(new St(ob, 2, s.a, s.b));
                        }
                    }
                    for (St t : next) {
                        if (seen.add(t)) {
                            work.add(t);
                        }
                    }
                }
                if (!work.isEmpty()) {
                    truncated++;
                }
            }
            return out;
        }

        /** Call stack after an entry (push) or exit (pop if the top matches; allowed on an empty stack). */
        private static int[] call(int[] a, int site, boolean entry, int d) {
            if (entry) {
                return a.length < d ? push(a, site) : null;
            }
            if (a.length == 0) {
                return EMPTY;
            }
            return a[a.length - 1] == site ? pop(a) : null;
        }
    }
}
