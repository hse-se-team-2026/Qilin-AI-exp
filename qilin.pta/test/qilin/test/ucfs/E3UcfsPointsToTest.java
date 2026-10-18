package qilin.test.ucfs;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.Test;
import org.ucfs.grammar.combinator.Grammar;
import org.ucfs.grammar.combinator.regexp.Concat;
import org.ucfs.grammar.combinator.regexp.Many;
import org.ucfs.grammar.combinator.regexp.Nt;
import org.ucfs.rsm.symbol.Term;
import qilin.CoreConfig;
import qilin.core.PTA;
import qilin.core.PTAScene;
import qilin.core.pag.AllocNode;
import qilin.core.pag.ArrayElement;
import qilin.core.pag.ContextField;
import qilin.core.pag.FieldRefNode;
import qilin.core.pag.GlobalVarNode;
import qilin.core.pag.LocalVarNode;
import qilin.core.pag.Node;
import qilin.core.pag.PAG;
import qilin.core.pag.ValNode;
import qilin.core.pag.VarNode;
import qilin.test.util.JunitTests;
import qilin.ucfs.PagExport;
import qilin.ucfs.PtLabels;
import qilin.ucfs.UcfsGraph;
import qilin.ucfs.UcfsPointsTo;
import qilin.util.PTAUtils;
import soot.ArrayType;
import soot.Local;
import soot.RefType;
import soot.SootMethod;
import soot.Type;
import soot.Unit;
import soot.Value;
import soot.jimple.InvokeExpr;
import soot.jimple.StaticInvokeExpr;
import soot.jimple.Stmt;
import soot.jimple.spark.pag.SparkField;

/**
 * E3-S3 acceptance check (docs/ai/tickets/E3-S3.md): UCFS computes points-to sets of small
 * programs. UcfsPointsTo.solve(pta) = PagExport + PointsToGrammar (flowsTo with fields) + UCFS
 * from the allocation vertices; the answer is a map CI variable -> CI objects.
 *
 * <p>Independent oracles, computed in this test from the PAG maps (not from the export, not by
 * UCFS):
 * <ol>
 *   <li>REF: field-sensitive Andersen fixpoint over the PAG edges without ContextField ends (the
 *       same input as E3.md D1-D3), without type filtering. flowsTo of Sridharan et al. 2005 is
 *       Andersen as CFL-reachability, so UCFS must equal REF on every variable;</li>
 *   <li>REF_T: the same fixpoint with the filters of Qilin's Solver (declared-type filter on
 *       every propagation, PTAUtils.castNeverFails; field-node types as ContextField; no
 *       store/load on empty arrays; the ROOT object, numbered 0, is invisible, E3.md R4b). It must equal
 *       Spark's own CI points-to sets: this validates that the reference reads the graph the way
 *       Spark does;</li>
 *   <li>Spark (the analysis that ran): every Spark points-to set is a subset of the UCFS set
 *       (UCFS lacks only the type filter, E3.md R1/R2);</li>
 *   <li>a second grammar through the same export and solver: new assign* (no fields) against a
 *       BFS over new/assign edges;</li>
 *   <li>hand facts from the source of Receiver2This and ArrayElemTypeFiltering (Assert calls).</li>
 * </ol>
 */
public class E3UcfsPointsToTest extends JunitTests {

    private static final String P = "qilin.microben.core.";

    /**
     * Programs: every main class of qilin.microben core (qilin.microben/src/qilin/microben/core)
     * whose exported graph is small, i.e. at most 2000 labeled edges under the arguments of
     * JunitTests (insens, -singleentry). The criterion and the list were fixed from the graph
     * sizes alone, before any UCFS answer was compared (docs/ai/tickets/E3-S3.md, "Контекст"): 43
     * programs have 62..1358 edges, the other 16 reach the JDK and have 545000..558000 edges.
     */
    static final String[] PROGRAMS = {
            "array.ArrayCopy", "array.ArrayElemTypeFiltering", "array.ArrayIndex", "array.MultiArrayComplex",
            "array.MultiArraySimple", "assign.CastSucc", "assign.InterAssign", "assign.NullPointer",
            "assign.Receiver2This", "assign.Recursion", "assign.ReturnValue0", "assign.ReturnValue1",
            "assign.ReturnValue2", "assign.ReturnValue3", "assign.SimpleAssign", "assign.StaticParameter",
            "call.StaticCall", "call.VirtualCall0", "call.VirtualCall1", "clinit.ClinitNewExpr",
            "clinit.ClinitStaticCall", "clinit.ClinitStaticLoad", "clinit.ClinitStaticStore",
            "exception.ExceptionChain", "exception.MethodThrow", "exception.SimpleException",
            "field.FieldSensitivity1", "field.FieldSensitivity2", "field.InstanceLoad", "field.InstanceStore",
            "global.StaticLoad", "global.StaticStore", "global.StringConstant", "natives.ArrayCopy",
            "natives.ObjectClone", "natives.PrivilegedActions0", "natives.PrivilegedActions2",
            "natives.RefArrayGet", "natives.RefArraySet", "natives.SystemIn", "reflog.ArrayNewInstance",
            "reflog.ClassForName", "reflog.DoopRefBug",
    };

    // ---------------------------------------------------------------- reference fixpoint
    private record FieldKey(AllocNode base, SparkField field) {
    }

    private static Node ci(Node n) {
        if (n instanceof VarNode v) {
            return v.base();
        }
        return ((AllocNode) n).base();
    }

    /** CI edges of the global PAG without ContextField ends, read through the inverse maps. */
    private static final class Edges {
        final List<Node[]> alloc = new ArrayList<>();   // {o, v}
        final List<Node[]> assign = new ArrayList<>();  // {u, v}
        final List<Object[]> load = new ArrayList<>();  // {x, f, z}   z = x.f
        final List<Object[]> store = new ArrayList<>(); // {y, x, f}   x.f = y

        Edges(PAG pag) {
            Set<List<Object>> seen = new HashSet<>();
            for (ValNode v : pag.getValNodeNumberer()) {
                if (v instanceof ContextField) {
                    continue;
                }
                for (ValNode u : pag.simpleInvLookup(v)) {
                    if (!(u instanceof ContextField) && seen.add(List.of("a", ci(u), ci(v)))) {
                        assign.add(new Node[]{ci(u), ci(v)});
                    }
                }
                if (v instanceof VarNode var) {
                    for (AllocNode o : pag.allocInvLookup(var)) {
                        if (seen.add(List.of("n", ci(o), ci(var)))) {
                            alloc.add(new Node[]{ci(o), ci(var)});
                        }
                    }
                    for (FieldRefNode fr : pag.loadInvLookup(var)) {
                        if (seen.add(List.of("l", ci(fr.getBase()), fr.getField(), ci(var)))) {
                            load.add(new Object[]{ci(fr.getBase()), fr.getField(), ci(var)});
                        }
                    }
                    for (FieldRefNode fr : pag.storeLookup(var)) {
                        if (seen.add(List.of("s", ci(var), ci(fr.getBase()), fr.getField()))) {
                            store.add(new Object[]{ci(var), ci(fr.getBase()), fr.getField()});
                        }
                    }
                }
            }
        }
    }

    /** Field-node type as qilin.core.pag.ContextField computes it. */
    private static Type fieldType(AllocNode base, SparkField f) {
        if (!CoreConfig.v().getPtaConfig().preciseArrayElement) {
            return RefType.v("java.lang.Object");
        }
        if (f instanceof ArrayElement) {
            return ((ArrayType) base.getType()).getArrayElementType();
        }
        return f.getType();
    }

    private static boolean emptyArray(AllocNode o) {
        return PTAUtils.isEmptyArray(o.base());
    }

    /**
     * Andersen fixpoint (worklist). typed = false: pure CFL semantics (REF); typed = true:
     * Qilin's filters (REF_T). withFields = false: only new and assign edges (no-fields grammar).
     * Keys of the points-to map: CI variables and FieldKey (object, field).
     */
    private static Map<Node, Set<AllocNode>> andersen(Edges g, boolean typed, boolean withFields) {
        return andersen(g, typed, withFields, Set.of());
    }

    /** As above; objects in {@code invisible} never enter a points-to set (REF_T only, see zeroNumbered). */
    private static Map<Node, Set<AllocNode>> andersen(Edges g, boolean typed, boolean withFields, Set<AllocNode> invisible) {
        Map<Object, Set<AllocNode>> pts = new HashMap<>();
        Map<Node, List<Node>> assignOut = new HashMap<>();
        Map<Node, List<Object[]>> storeBySrc = new HashMap<>();  // y -> {x, f}
        Map<Node, List<Object[]>> storeByBase = new HashMap<>(); // x -> {y, f}
        Map<Node, List<Object[]>> loadByBase = new HashMap<>();  // x -> {f, z}
        Map<SparkField, List<Node[]>> loadByField = new HashMap<>(); // f -> {x, z}
        for (Node[] e : g.assign) {
            assignOut.computeIfAbsent(e[0], k -> new ArrayList<>()).add(e[1]);
        }
        if (withFields) {
            for (Object[] e : g.store) {
                storeBySrc.computeIfAbsent((Node) e[0], k -> new ArrayList<>()).add(new Object[]{e[1], e[2]});
                storeByBase.computeIfAbsent((Node) e[1], k -> new ArrayList<>()).add(new Object[]{e[0], e[2]});
            }
            for (Object[] e : g.load) {
                loadByBase.computeIfAbsent((Node) e[0], k -> new ArrayList<>()).add(new Object[]{e[1], e[2]});
                loadByField.computeIfAbsent((SparkField) e[1], k -> new ArrayList<>()).add(new Node[]{(Node) e[0], (Node) e[2]});
            }
        }
        java.util.ArrayDeque<Object> work = new java.util.ArrayDeque<>();
        java.util.function.BiConsumer<Object, Set<AllocNode>> flow = (to, objs) -> {
            boolean changed = false;
            for (AllocNode o : objs) {
                Type filter = null;
                if (typed) {
                    filter = to instanceof FieldKey fk ? fieldType(fk.base(), fk.field()) : ((Node) to).getType();
                }
                changed |= addTo(pts, to, o, filter);
            }
            if (changed) {
                work.add(to);
            }
        };
        for (Node[] e : g.alloc) {
            if (!invisible.contains((AllocNode) e[0])) {
                flow.accept(e[1], Set.of((AllocNode) e[0]));
            }
        }
        while (!work.isEmpty()) {
            Object n = work.poll();
            Set<AllocNode> cur = new HashSet<>(pts.getOrDefault(n, Set.of()));
            if (n instanceof FieldKey fk) {
                for (Node[] xz : loadByField.getOrDefault(fk.field(), List.of())) {
                    if (pts.getOrDefault(xz[0], Set.of()).contains(fk.base())) {
                        flow.accept(xz[1], cur);
                    }
                }
                continue;
            }
            Node v = (Node) n;
            for (Node to : assignOut.getOrDefault(v, List.of())) {
                flow.accept(to, cur);
            }
            for (Object[] xf : storeBySrc.getOrDefault(v, List.of())) {
                for (AllocNode b : new ArrayList<>(pts.getOrDefault(xf[0], Set.of()))) {
                    if (!(typed && emptyArray(b))) {
                        flow.accept(new FieldKey(b, (SparkField) xf[1]), cur);
                    }
                }
            }
            for (Object[] yf : storeByBase.getOrDefault(v, List.of())) {
                Set<AllocNode> ys = new HashSet<>(pts.getOrDefault(yf[0], Set.of()));
                for (AllocNode b : cur) {
                    if (!(typed && emptyArray(b))) {
                        flow.accept(new FieldKey(b, (SparkField) yf[1]), ys);
                    }
                }
            }
            for (Object[] fz : loadByBase.getOrDefault(v, List.of())) {
                for (AllocNode b : cur) {
                    if (!(typed && emptyArray(b))) {
                        flow.accept(fz[1], new HashSet<>(pts.getOrDefault(new FieldKey(b, (SparkField) fz[0]), Set.of())));
                    }
                }
            }
        }
        Map<Node, Set<AllocNode>> result = new HashMap<>();
        pts.forEach((k, val) -> {
            if (k instanceof Node node && !val.isEmpty()) {
                result.put(node, val);
            }
        });
        return result;
    }

    private static <K> boolean addTo(Map<K, Set<AllocNode>> m, K key, AllocNode o, Type filter) {
        if (filter != null && !PTAUtils.castNeverFails(o.getType(), filter)) {
            return false;
        }
        return m.computeIfAbsent(key, k -> new HashSet<>()).add(o);
    }

    /**
     * CI objects whose context node has number 0. Qilin's HybridPointsToSet uses 0 as the mark of
     * an empty slot, so such an object never shows up in a Spark points-to set. In insens runs
     * this is the ROOT object (PTA's root node, ROOT -> this of FakeMain.fakeMain in
     * CallGraphBuilder.getEntryPoints). REF_T mirrors it; UCFS and REF keep the edge (E3.md R4b).
     */
    private static Set<AllocNode> zeroNumbered(PAG pag) {
        Set<AllocNode> s = new HashSet<>();
        for (AllocNode a : pag.getAlloc().keySet()) {
            if (a.getNumber() == 0) {
                s.add(a.base());
            }
        }
        return s;
    }

    /** Spark's CI points-to set of every CI variable that has one. */
    private static Map<Node, Set<AllocNode>> spark(PTA pta, Set<Node> vars) {
        Map<Node, Set<AllocNode>> m = new HashMap<>();
        for (Node v : vars) {
            Set<AllocNode> s = new HashSet<>(pta.reachingObjects(v).toCIPointsToSet().toCollection());
            if (!s.isEmpty()) {
                m.put(v, s);
            }
        }
        return m;
    }

    private static Map<Node, Set<AllocNode>> normalize(Map<? extends Node, ? extends Set<? extends AllocNode>> m) {
        Map<Node, Set<AllocNode>> r = new HashMap<>();
        m.forEach((k, v) -> {
            if (!v.isEmpty()) {
                r.put(k, new HashSet<>(v));
            }
        });
        return r;
    }

    private static Set<Node> ciVars(PAG pag) {
        Set<Node> vars = new HashSet<>();
        for (ValNode v : pag.getValNodeNumberer()) {
            if (v instanceof VarNode var && (var.base() instanceof LocalVarNode || var.base() instanceof GlobalVarNode)) {
                vars.add(var.base());
            }
        }
        return vars;
    }

    /** First differences of two points-to maps, for failure messages. */
    private static String diff(Map<Node, Set<AllocNode>> a, Map<Node, Set<AllocNode>> b) {
        List<String> out = new ArrayList<>();
        Set<Node> keys = new HashSet<>(a.keySet());
        keys.addAll(b.keySet());
        for (Node k : keys) {
            Set<AllocNode> x = a.getOrDefault(k, Set.of());
            Set<AllocNode> y = b.getOrDefault(k, Set.of());
            if (!x.equals(y) && out.size() < 3) {
                Set<AllocNode> onlyA = new HashSet<>(x);
                onlyA.removeAll(y);
                Set<AllocNode> onlyB = new HashSet<>(y);
                onlyB.removeAll(x);
                out.add(k + " only-first=" + onlyA + " only-second=" + onlyB);
            }
        }
        return String.join("; ", out);
    }

    private static int pairs(Map<Node, Set<AllocNode>> m) {
        return m.values().stream().mapToInt(Set::size).sum();
    }

    /** The no-fields grammar flowsTo -> new assign*, defined here, run through UcfsPointsTo. */
    public static final class NoFieldsGrammar extends Grammar {
        public NoFieldsGrammar() {
            Nt s = new Nt(new Concat(new Term<>(PtLabels.NEW), new Many(new Term<>(PtLabels.ASSIGN))), "S");
            getNonTerms().add(s);
            asStart(s);
        }
    }

    // ------------------------------------------------------------------------------- tests
    @Test
    public void allProgramsAgainstReferences() {
        List<String> failures = new ArrayList<>();
        int totalUcfs = 0;
        int totalSpark = 0;
        for (String p : PROGRAMS) {
            PTAScene.junitReset();
            PTA pta = run(P + p, "insens");
            Edges g = new Edges(pta.getPag());
            Map<Node, Set<AllocNode>> ref = andersen(g, false, true);
            Set<AllocNode> zero = zeroNumbered(pta.getPag());
            Map<Node, Set<AllocNode>> refT = andersen(g, true, true, zero);
            Map<Node, Set<AllocNode>> sp = spark(pta, ciVars(pta.getPag()));
            long t0 = System.nanoTime();
            Map<Node, Set<AllocNode>> ucfs = normalize(UcfsPointsTo.solve(pta));
            long ms = (System.nanoTime() - t0) / 1_000_000;

            // 4: a second grammar through the same export and solver
            UcfsGraph graph = PagExport.export(pta);
            Map<Node, Set<AllocNode>> ucfsNoFields = normalize(UcfsPointsTo.solve(graph, new NoFieldsGrammar()));
            Map<Node, Set<AllocNode>> refNoFields = andersen(g, false, false);

            int missing = 0;
            for (Map.Entry<Node, Set<AllocNode>> e : sp.entrySet()) {
                Set<AllocNode> u = ucfs.getOrDefault(e.getKey(), Set.of());
                for (AllocNode o : e.getValue()) {
                    if (!u.contains(o)) {
                        missing++;
                    }
                }
            }
            int extra = pairs(ucfs) - (pairs(sp) - missing);
            System.out.println("E3UcfsPointsToTest " + p + ": vertices=" + graph.getVertices().size()
                    + " edges=" + graph.getEdges().size() + " fields=" + graph.getFields().size()
                    + " ucfsPairs=" + pairs(ucfs) + " sparkPairs=" + pairs(sp) + " missing=" + missing
                    + " extra=" + extra + " noFieldsPairs=" + pairs(ucfsNoFields) + " ucfsMs=" + ms);
            totalUcfs += pairs(ucfs);
            totalSpark += pairs(sp);
            if (!ucfs.equals(ref)) {
                failures.add(p + ": UCFS != REF (field-sensitive Andersen without type filter)");
            }
            if (!refT.equals(sp)) {
                failures.add(p + ": REF_T != Spark (reference with Qilin's filters): " + diff(refT, sp));
            }
            if (missing != 0) {
                failures.add(p + ": " + missing + " Spark pairs missing from UCFS");
            }
            if (!ucfsNoFields.equals(refNoFields)) {
                failures.add(p + ": UCFS(new assign*) != BFS over new/assign edges");
            }
            if (zero.size() != 1 || !zero.iterator().next().equals(pta.getRootNode().base())) {
                failures.add(p + ": expected exactly the ROOT object with context number 0, got " + zero);
            }
            if (ucfs.isEmpty()) {
                failures.add(p + ": empty UCFS answer");
            }
        }
        System.out.println("E3UcfsPointsToTest total: programs=" + PROGRAMS.length + " ucfsPairs=" + totalUcfs
                + " sparkPairs=" + totalSpark);
        assertTrue(String.join("\n", failures), failures.isEmpty());
    }

    /** Assert.mayAlias/notAlias(a, b) calls with two locals in reachable methods of the program. */
    private record AliasQuery(SootMethod m, Local a, Local b, boolean mayAlias) {
    }

    private static List<AliasQuery> queries(PTA pta) {
        List<AliasQuery> qs = new ArrayList<>();
        for (SootMethod sm : pta.getNakedReachableMethods()) {
            if (sm.isNative() || sm.isPhantom()) {
                continue;
            }
            for (Unit u : PTAUtils.getMethodBody(sm).getUnits()) {
                Stmt s = (Stmt) u;
                if (s.containsInvokeExpr() && s.getInvokeExpr() instanceof StaticInvokeExpr ie) {
                    String sig = ie.getMethodRef().getSignature();
                    boolean may = sig.equals("<qilin.microben.utils.Assert: void mayAlias(java.lang.Object,java.lang.Object)>");
                    boolean not = sig.equals("<qilin.microben.utils.Assert: void notAlias(java.lang.Object,java.lang.Object)>");
                    if (!may && !not) {
                        continue;
                    }
                    Value a = ie.getArg(0);
                    Value b = ie.getArg(1);
                    if (a instanceof Local la && b instanceof Local lb) {
                        qs.add(new AliasQuery(sm, la, lb, may));
                    }
                }
            }
        }
        return qs;
    }

    private static boolean ucfsAlias(PTA pta, Map<Node, Set<AllocNode>> ucfs, AliasQuery q) {
        Set<AllocNode> a = ucfs.getOrDefault(pta.getPag().findLocalVarNode(q.a()), Set.of());
        Set<AllocNode> b = ucfs.getOrDefault(pta.getPag().findLocalVarNode(q.b()), Set.of());
        return a.stream().anyMatch(b::contains);
    }

    /**
     * Receiver2This: B.foo has mayAlias(this, o), A.foo has notAlias(this, o) (source comments).
     * With the receiver binding of the analysis (E3.md D2) UCFS answers both as the source says.
     * ArrayElemTypeFiltering: {@code I[] array = new G[10]; array[0] = g; array[1] = h; I i =
     * array[0]; notAlias(i, h);} with G, H unrelated. With -pae (JunitTests) Spark types the
     * element field of the G[] object as G and drops h; UCFS has no type filter (E3.md R1), so it
     * answers that i may alias h. The other three assertions (mayAlias) hold under UCFS.
     */
    @Test
    public void handFactsReceiver2ThisAndArrayElemTypeFiltering() {
        PTAScene.junitReset();
        PTA pta = run(P + "assign.Receiver2This", "insens");
        Map<Node, Set<AllocNode>> ucfs = normalize(UcfsPointsTo.solve(pta));
        List<AliasQuery> qs = queries(pta);
        assertEquals("Receiver2This has 2 alias assertions: " + qs, 2, qs.size());
        for (AliasQuery q : qs) {
            assertEquals("Receiver2This " + q.m().getDeclaringClass().getShortName() + ".foo: "
                    + (q.mayAlias() ? "mayAlias" : "notAlias"), q.mayAlias(), ucfsAlias(pta, ucfs, q));
        }

        PTAScene.junitReset();
        pta = run(P + "array.ArrayElemTypeFiltering", "insens");
        ucfs = normalize(UcfsPointsTo.solve(pta));
        qs = queries(pta);
        assertEquals("ArrayElemTypeFiltering has 4 alias assertions: " + qs, 4, qs.size());
        int notAlias = 0;
        for (AliasQuery q : qs) {
            boolean spark = pta.reachingObjects(q.a()).toCIPointsToSet()
                    .hasNonEmptyIntersection(pta.reachingObjects(q.b()).toCIPointsToSet());
            assertEquals("Spark answers as the source says: " + q, q.mayAlias(), spark);
            if (q.mayAlias()) {
                assertTrue("mayAlias holds under UCFS: " + q, ucfsAlias(pta, ucfs, q));
            } else {
                notAlias++;
                assertTrue("UCFS has no element type filter, so i may alias h (R1): " + q, ucfsAlias(pta, ucfs, q));
            }
        }
        assertEquals(1, notAlias);
    }

    /** Every mayAlias assertion with two locals holds under UCFS (soundness w.r.t. the source). */
    @Test
    public void mayAliasAssertionsHold() {
        int n = 0;
        List<String> bad = new ArrayList<>();
        for (String p : PROGRAMS) {
            PTAScene.junitReset();
            PTA pta = run(P + p, "insens");
            Map<Node, Set<AllocNode>> ucfs = normalize(UcfsPointsTo.solve(pta));
            for (AliasQuery q : queries(pta)) {
                if (q.mayAlias()) {
                    n++;
                    if (!ucfsAlias(pta, ucfs, q)) {
                        bad.add(p + " " + q);
                    }
                }
            }
        }
        System.out.println("E3UcfsPointsToTest mayAlias assertions checked: " + n);
        assertTrue("mayAlias assertions failing under UCFS: " + bad, bad.isEmpty());
        assertTrue("the programs have mayAlias assertions", n >= 20);
    }
}
