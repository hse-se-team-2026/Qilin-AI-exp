package qilin.test.ucfs;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.BiPredicate;
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
import qilin.core.pag.MergedNewExpr;
import qilin.core.pag.MethodPAG;
import qilin.core.pag.Node;
import qilin.core.pag.PAG;
import qilin.core.pag.Parm;
import qilin.core.pag.ValNode;
import qilin.core.pag.VarNode;
import qilin.test.util.JunitTests;
import qilin.ucfs.LabeledEdge;
import qilin.ucfs.PagExport;
import qilin.ucfs.PtLabels;
import qilin.ucfs.UcfsGraph;
import qilin.ucfs.UcfsPointsTo;
import qilin.ucfs.UcfsSolver;
import qilin.ucfs.VertexPair;
import qilin.ucfs.grammar.PointsToGrammar;
import qilin.util.PTAUtils;
import soot.ArrayType;
import soot.Local;
import soot.RefType;
import soot.SootMethod;
import soot.Type;
import soot.Unit;
import soot.Value;
import soot.jimple.CastExpr;
import soot.jimple.CaughtExceptionRef;
import soot.jimple.StaticInvokeExpr;
import soot.jimple.Stmt;
import soot.jimple.spark.pag.SparkField;
import soot.util.queue.QueueReader;

/**
 * E3-S3 acceptance check (docs/ai/tickets/E3-S3.md): UCFS computes points-to sets of small
 * programs. UcfsPointsTo.solve(pta) = PagExport + PointsToGrammar (flowsTo with fields) + UCFS
 * from the allocation vertices; the answer is a map CI variable -> CI objects.
 *
 * <p>What is independent here, and what is not (E3.md D1, D7). The input of UCFS is the global PAG
 * of Spark. Part of its "new" edges were made by the solver of Spark from points-to sets, not by a
 * statement: receiver object -> this (CallGraphBuilder.addVirtualEdge), thrown object -> catch
 * variable or throw node (ExceptionHandler.dispatch), object -> parameter of Finalizer.register.
 * The references below read the same PAG maps, so they are independent of UCFS for the field part
 * (store, alias, load) and for assign/new propagation, not for those edges. The test counts them
 * (derivedNew...) and the UCFS answer without them (pairsWithoutDerivedNew). The second export
 * mode without the receiver edges is E3-S3b (E3ReceiverAssignTest).
 *
 * <p>Oracles, computed in this test (none by the code under test):
 * <ol>
 *   <li>UCFS itself, called here directly: UcfsSolver.reachablePairs (E2 API) on the export with
 *       PointsToGrammar from the allocation vertices; solve(pta) must return the same map
 *       (critic-E3 M1: the evidence that UCFS answers does not rest on solve(pta));</li>
 *   <li>REF: field-sensitive Andersen fixpoint over the PAG edges without ContextField ends (the
 *       same input as E3.md D1-D3), without type filtering. flowsTo of Sridharan et al. 2005 is
 *       Andersen as CFL-reachability, so UCFS must equal REF on every variable;</li>
 *   <li>REF_T: the same fixpoint with the filters of Qilin's Solver; it must equal Spark's own CI
 *       points-to sets, which validates that the reference reads the graph the way Spark does.
 *       Spark subset of UCFS follows from REF = UCFS and REF_T = Spark (filters only remove
 *       facts); it is counted (missing) but is not a separate oracle;</li>
 *   <li>every extra pair of UCFS over Spark gets a class: the filters are switched on one by one
 *       (ROOT invisible = R4b, declared type of the variables other than cast nodes and of the
 *       field nodes = R1, type of a cast node = R2, no store/load on empty arrays = R5); a pair
 *       removed by step k has class k. The last step is REF_T = Spark, so every extra pair gets
 *       exactly one class. Each line also lists the filters that remove the pair when switched on
 *       alone (a pair can be removed by two of them, e.g. by the element type of an array and by a
 *       cast that Soot inserted before the store);</li>
 *   <li>a second grammar through the same export and solver: new assign* (no fields) against a
 *       BFS over new/assign edges;</li>
 *   <li>hand facts from the source of Receiver2This and ArrayElemTypeFiltering, and every
 *       Assert.mayAlias of the 43 programs.</li>
 * </ol>
 */
public class E3UcfsPointsToTest extends JunitTests {

    static final String P = "qilin.microben.core.";

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
    record FieldKey(AllocNode base, SparkField field) {
    }

    static Node ci(Node n) {
        if (n instanceof VarNode v) {
            return v.base();
        }
        return ((AllocNode) n).base();
    }

    /** CI edges of the global PAG without ContextField ends, read through the inverse maps. */
    static final class Edges {
        final List<Node[]> alloc = new ArrayList<>();   // {o, v}
        final List<Node[]> assign = new ArrayList<>();  // {u, v}
        final List<Object[]> load = new ArrayList<>();  // {x, f, z}   z = x.f
        final List<Object[]> store = new ArrayList<>(); // {y, x, f}   x.f = y

        private Edges() {
        }

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

        /** A copy without the alloc edges {o, v} with drop(o, v), plus the assign edges extraAssign. */
        Edges with(BiPredicate<Node, Node> drop, List<Node[]> extraAssign) {
            Edges r = new Edges();
            for (Node[] e : alloc) {
                if (!drop.test(e[0], e[1])) {
                    r.alloc.add(e);
                }
            }
            r.assign.addAll(assign);
            Set<List<Node>> seen = new HashSet<>();
            for (Node[] e : assign) {
                seen.add(List.of(e[0], e[1]));
            }
            for (Node[] e : extraAssign) {
                if (seen.add(List.of(e[0], e[1]))) {
                    r.assign.add(e);
                }
            }
            r.load.addAll(load);
            r.store.addAll(store);
            return r;
        }

        /** The labeled edges of these PAG edges over the ids of {@code g} (forward and "_bar"). */
        Set<LabeledEdge> labeled(UcfsGraph g) {
            Set<LabeledEdge> s = new HashSet<>();
            java.util.function.BiConsumer<int[], String> add = (ft, l) -> {
                s.add(new LabeledEdge(ft[0], l, ft[1]));
                s.add(new LabeledEdge(ft[1], PtLabels.bar(l), ft[0]));
            };
            for (Node[] e : alloc) {
                add.accept(new int[]{g.vertexOf(e[0]), g.vertexOf(e[1])}, PtLabels.NEW);
            }
            for (Node[] e : assign) {
                add.accept(new int[]{g.vertexOf(e[0]), g.vertexOf(e[1])}, PtLabels.ASSIGN);
            }
            for (Object[] e : load) {
                add.accept(new int[]{g.vertexOf((Node) e[0]), g.vertexOf((Node) e[2])}, PtLabels.load(g.fieldIndex((SparkField) e[1])));
            }
            for (Object[] e : store) {
                add.accept(new int[]{g.vertexOf((Node) e[0]), g.vertexOf((Node) e[1])}, PtLabels.store(g.fieldIndex((SparkField) e[2])));
            }
            return s;
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

    private static boolean isCastNode(Object n) {
        return n instanceof LocalVarNode lv && lv.getVariable() instanceof CastExpr;
    }

    /**
     * Filters of Qilin's solver that the reference can switch on: objects that never enter a set
     * (ROOT, R4b); the type of a cast node (R2); the declared type of the other variables and of the
     * field nodes (PTAUtils.castNeverFails; field-node types as ContextField; R1); no store/load on
     * empty arrays (R5).
     */
    record Filters(Set<AllocNode> invisible, boolean castTypes, boolean declaredTypes, boolean emptyArrays) {
        static final Filters NONE = new Filters(Set.of(), false, false, false);
    }

    /**
     * Andersen fixpoint (worklist) with the given filters. withFields = false: only new and assign
     * edges (no-fields grammar). Keys of the result: CI variables.
     */
    static Map<Node, Set<AllocNode>> andersen(Edges g, Filters fl, boolean withFields) {
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
            Type filter = null;
            if (to instanceof FieldKey fk) {
                filter = fl.declaredTypes() ? fieldType(fk.base(), fk.field()) : null;
            } else if (isCastNode(to) ? fl.castTypes() : fl.declaredTypes()) {
                filter = ((Node) to).getType();
            }
            for (AllocNode o : objs) {
                changed |= addTo(pts, to, o, filter);
            }
            if (changed) {
                work.add(to);
            }
        };
        for (Node[] e : g.alloc) {
            if (!fl.invisible().contains((AllocNode) e[0])) {
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
                    if (!(fl.emptyArrays() && emptyArray(b))) {
                        flow.accept(new FieldKey(b, (SparkField) xf[1]), cur);
                    }
                }
            }
            for (Object[] yf : storeByBase.getOrDefault(v, List.of())) {
                Set<AllocNode> ys = new HashSet<>(pts.getOrDefault(yf[0], Set.of()));
                for (AllocNode b : cur) {
                    if (!(fl.emptyArrays() && emptyArray(b))) {
                        flow.accept(new FieldKey(b, (SparkField) yf[1]), ys);
                    }
                }
            }
            for (Object[] fz : loadByBase.getOrDefault(v, List.of())) {
                for (AllocNode b : cur) {
                    if (!(fl.emptyArrays() && emptyArray(b))) {
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
    static Set<AllocNode> zeroNumbered(PAG pag) {
        Set<AllocNode> s = new HashSet<>();
        for (AllocNode a : pag.getAlloc().keySet()) {
            if (a.getNumber() == 0) {
                s.add(a.base());
            }
        }
        return s;
    }

    /** Spark's CI points-to set of every CI variable that has one. */
    static Map<Node, Set<AllocNode>> spark(PTA pta, Set<Node> vars) {
        Map<Node, Set<AllocNode>> m = new HashMap<>();
        for (Node v : vars) {
            Set<AllocNode> s = new HashSet<>(pta.reachingObjects(v).toCIPointsToSet().toCollection());
            if (!s.isEmpty()) {
                m.put(v, s);
            }
        }
        return m;
    }

    static Map<Node, Set<AllocNode>> normalize(Map<? extends Node, ? extends Set<? extends AllocNode>> m) {
        Map<Node, Set<AllocNode>> r = new HashMap<>();
        m.forEach((k, v) -> {
            if (!v.isEmpty()) {
                r.put(k, new HashSet<>(v));
            }
        });
        return r;
    }

    static Set<Node> ciVars(PAG pag) {
        Set<Node> vars = new HashSet<>();
        for (ValNode v : pag.getValNodeNumberer()) {
            if (v instanceof VarNode var && (var.base() instanceof LocalVarNode || var.base() instanceof GlobalVarNode)) {
                vars.add(var.base());
            }
        }
        return vars;
    }

    /** First differences of two points-to maps, for failure messages. */
    static String diff(Map<Node, Set<AllocNode>> a, Map<Node, Set<AllocNode>> b) {
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

    static int pairs(Map<Node, Set<AllocNode>> m) {
        return m.values().stream().mapToInt(Set::size).sum();
    }

    /** pairs b \ a, as {var, object} */
    static List<Node[]> minus(Map<Node, Set<AllocNode>> b, Map<Node, Set<AllocNode>> a) {
        List<Node[]> out = new ArrayList<>();
        b.forEach((v, objs) -> {
            for (AllocNode o : objs) {
                if (!a.getOrDefault(v, Set.of()).contains(o)) {
                    out.add(new Node[]{v, o});
                }
            }
        });
        return out;
    }

    /** UCFS called directly (E2 API): PointsToGrammar from the allocation vertices of the graph. */
    static Map<Node, Set<AllocNode>> ucfsDirect(UcfsGraph g, List<LabeledEdge> edges) {
        Set<VertexPair> ps = UcfsSolver.reachablePairs(edges, new PointsToGrammar(g.getFields().size()), g.allocVertices());
        Map<Node, Set<AllocNode>> m = new HashMap<>();
        for (VertexPair p : ps) {
            Node o = g.nodeOf(p.getFrom());
            Node v = g.nodeOf(p.getTo());
            if (o instanceof AllocNode a && v instanceof VarNode) {
                m.computeIfAbsent(v, k -> new HashSet<>()).add(a);
            }
        }
        return m;
    }

    // ------------------------------------------------------- classes of the "new" edges (E3.md D1)
    enum NewKind { STATEMENT, ROOT, RECEIVER, EXCEPTION, FINALIZER, OTHER }

    /**
     * Allocation edges written by statements: the internal edges object -> variable of the
     * MethodPAG of every reachable method (Solver.addToPAG adds exactly these, after the heap
     * abstraction of -mh, which merges StringBuilder/StringBuffer/Throwable objects of one type
     * into a MergedNewExpr object). Keys: [object, variable] and ["merged", type, variable].
     */
    static Set<List<Object>> statementAllocs(PTA pta) {
        Set<List<Object>> s = new HashSet<>();
        for (SootMethod m : pta.getNakedReachableMethods()) {
            if (m.isPhantom()) {
                continue;
            }
            MethodPAG mp = pta.getPag().getMethodPAG(m);
            QueueReader<Node> r = mp.getInternalReader().clone();
            while (r.hasNext()) {
                Node src = r.next();
                Node dst = r.next();
                if (src instanceof AllocNode a && dst instanceof VarNode v) {
                    s.add(List.of(ci(a), ci(v)));
                    s.add(List.of("merged", a.getType(), ci(v)));
                }
            }
        }
        return s;
    }

    /**
     * Class of the CI allocation edge o -> v: written by a statement; ROOT -> this of the fake main
     * method (CallGraphBuilder.getEntryPoints); or made by the solver from points-to sets:
     * receiver object -> this (CallGraphBuilder.addVirtualEdge), thrown object -> catch variable
     * or throw node of a method (ExceptionHandler.dispatch), object -> parameter 0 of
     * Finalizer.register (Solver.handleImplicitCallToFinalizerRegister). OTHER must not occur.
     */
    static NewKind classify(Set<List<Object>> stmts, AllocNode root, Node o, Node v) {
        boolean merged = o instanceof AllocNode a && a.getNewExpr() instanceof MergedNewExpr;
        if (stmts.contains(List.of(o, v)) || (merged && stmts.contains(List.of("merged", o.getType(), v)))) {
            return NewKind.STATEMENT;
        }
        if (o.equals(root)) {
            return NewKind.ROOT;
        }
        if (v instanceof LocalVarNode lv) {
            if (lv.isThis()) {
                return NewKind.RECEIVER;
            }
            Object var = lv.getVariable();
            if ((var instanceof Parm p && p.isThrowRet()) || var instanceof CaughtExceptionRef) {
                return NewKind.EXCEPTION;
            }
            if (var instanceof Parm p && p.getIndex() == 0
                    && p.method().getSignature().equals("<java.lang.ref.Finalizer: void register(java.lang.Object)>")) {
                return NewKind.FINALIZER;
            }
        }
        return NewKind.OTHER;
    }

    /** Counts of the classes of the "new" edges of a graph. */
    static Map<NewKind, Integer> newKinds(PTA pta, UcfsGraph g, Set<LabeledEdge> derivedOut) {
        Set<List<Object>> stmts = statementAllocs(pta);
        AllocNode root = pta.getRootNode().base();
        Map<NewKind, Integer> c = new java.util.EnumMap<>(NewKind.class);
        for (NewKind k : NewKind.values()) {
            c.put(k, 0);
        }
        for (LabeledEdge e : g.getEdges()) {
            if (e.getLabel().equals(PtLabels.NEW)) {
                NewKind k = classify(stmts, root, g.nodeOf(e.getFrom()), g.nodeOf(e.getTo()));
                c.merge(k, 1, Integer::sum);
                if (k != NewKind.STATEMENT && k != NewKind.ROOT && derivedOut != null) {
                    derivedOut.add(e);
                }
            }
        }
        return c;
    }

    static int derived(Map<NewKind, Integer> c) {
        return c.get(NewKind.RECEIVER) + c.get(NewKind.EXCEPTION) + c.get(NewKind.FINALIZER) + c.get(NewKind.OTHER);
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
        int[] total = new int[12];
        for (String p : PROGRAMS) {
            PTAScene.junitReset();
            PTA pta = run(P + p, "insens");
            Edges g = new Edges(pta.getPag());
            Set<AllocNode> zero = zeroNumbered(pta.getPag());
            Map<Node, Set<AllocNode>> ref = andersen(g, Filters.NONE, true);
            Map<Node, Set<AllocNode>> sp = spark(pta, ciVars(pta.getPag()));
            long t0 = System.nanoTime();
            Map<Node, Set<AllocNode>> ucfs = normalize(UcfsPointsTo.solve(pta));
            long ms = (System.nanoTime() - t0) / 1_000_000;
            UcfsGraph graph = PagExport.export(pta);
            Map<Node, Set<AllocNode>> direct = ucfsDirect(graph, graph.getEdges());

            // classes of the extra pairs: switch on the filters one by one (R4b, R1, R2, R5); a pair
            // removed by step k has class k. Also, which filters remove the pair when switched on alone.
            Filters[] steps = {
                    new Filters(zero, false, false, false),
                    new Filters(zero, false, true, false),
                    new Filters(zero, true, true, false),
                    new Filters(zero, true, true, true),
            };
            Filters[] alone = {
                    new Filters(zero, false, false, false),
                    new Filters(Set.of(), false, true, false),
                    new Filters(Set.of(), true, false, false),
                    new Filters(Set.of(), false, false, true),
            };
            String[] cls = {"R4b", "R1", "R2", "R5"};
            List<Map<Node, Set<AllocNode>>> single = new ArrayList<>();
            for (Filters f : alone) {
                single.add(andersen(g, f, true));
            }
            int[] perClass = new int[4];
            int[] bySingle = new int[4];
            Map<Node, Set<AllocNode>> prev = ref;
            List<String> extraLines = new ArrayList<>();
            for (int i = 0; i < steps.length; i++) {
                Map<Node, Set<AllocNode>> next = andersen(g, steps[i], true);
                for (Node[] vo : minus(prev, next)) {
                    perClass[i]++;
                    List<String> singles = new ArrayList<>();
                    for (int j = 0; j < alone.length; j++) {
                        if (!single.get(j).getOrDefault(vo[0], Set.of()).contains((AllocNode) vo[1])) {
                            singles.add(cls[j]);
                            bySingle[j]++;
                        }
                    }
                    extraLines.add("E3UcfsPointsToTest extra " + p + " class=" + cls[i] + " removedAloneBy=" + singles
                            + " " + vo[0] + " <- " + vo[1]);
                }
                prev = next;
            }
            Map<Node, Set<AllocNode>> refT = prev;

            // 5: a second grammar through the same export and solver
            Map<Node, Set<AllocNode>> ucfsNoFields = normalize(UcfsPointsTo.solve(graph, new NoFieldsGrammar()));
            Map<Node, Set<AllocNode>> refNoFields = andersen(g, Filters.NONE, false);

            // the "new" edges made by the solver, and the UCFS answer without them (E3.md D1)
            Set<LabeledEdge> derivedEdges = new HashSet<>();
            Map<NewKind, Integer> kinds = newKinds(pta, graph, derivedEdges);
            List<LabeledEdge> kept = new ArrayList<>();
            for (LabeledEdge e : graph.getEdges()) {
                boolean drop = derivedEdges.contains(e) || (e.getLabel().equals(PtLabels.bar(PtLabels.NEW))
                        && derivedEdges.contains(new LabeledEdge(e.getTo(), PtLabels.NEW, e.getFrom())));
                if (!drop) {
                    kept.add(e);
                }
            }
            Map<Node, Set<AllocNode>> without = ucfsDirect(graph, kept);
            Set<List<Object>> stmts = statementAllocs(pta);
            AllocNode root = pta.getRootNode().base();
            Map<Node, Set<AllocNode>> refWithout = andersen(g.with((o, v) -> {
                NewKind k = classify(stmts, root, o, v);
                return k != NewKind.STATEMENT && k != NewKind.ROOT;
            }, List.of()), Filters.NONE, true);

            int missing = minus(sp, ucfs).size();
            int extra = minus(ucfs, sp).size();
            int[] row = {pairs(ucfs), pairs(sp), missing, extra, perClass[0], perClass[1], perClass[2], perClass[3],
                    kinds.get(NewKind.STATEMENT) + kinds.get(NewKind.ROOT) + derived(kinds), derived(kinds),
                    kinds.get(NewKind.RECEIVER), pairs(without)};
            for (int i = 0; i < row.length; i++) {
                total[i] += row[i];
            }
            System.out.println("E3UcfsPointsToTest " + p + ": vertices=" + graph.getVertices().size()
                    + " edges=" + graph.getEdges().size() + " fields=" + graph.getFields().size()
                    + " ucfsPairs=" + row[0] + " sparkPairs=" + row[1] + " missing=" + missing + " extra=" + extra
                    + " extraR4b=" + perClass[0] + " extraR1=" + perClass[1] + " extraR2=" + perClass[2] + " extraR5=" + perClass[3]
                    + " noFieldsPairs=" + pairs(ucfsNoFields) + " newEdges=" + row[8] + " derivedNew=" + row[9]
                    + " derivedNewIntoThis=" + row[10] + " derivedNewException=" + kinds.get(NewKind.EXCEPTION)
                    + " derivedNewFinalizer=" + kinds.get(NewKind.FINALIZER) + " pairsWithoutDerivedNew=" + row[11]
                    + " ucfsMs=" + ms);
            extraLines.forEach(System.out::println);
            if (!direct.equals(ref)) {
                failures.add(p + ": UCFS (UcfsSolver.reachablePairs called by the test) != REF: " + diff(direct, ref));
            }
            if (!ucfs.equals(direct)) {
                failures.add(p + ": UcfsPointsTo.solve(pta) != UCFS called by the test: " + diff(ucfs, direct));
            }
            if (!refT.equals(sp)) {
                failures.add(p + ": REF_T != Spark (reference with Qilin's filters): " + diff(refT, sp));
            }
            if (perClass[0] + perClass[1] + perClass[2] + perClass[3] != extra) {
                failures.add(p + ": extra pairs " + extra + " != classified " + java.util.Arrays.toString(perClass));
            }
            if (missing != 0) {
                failures.add(p + ": " + missing + " Spark pairs missing from UCFS");
            }
            if (!ucfsNoFields.equals(refNoFields)) {
                failures.add(p + ": UCFS(new assign*) != BFS over new/assign edges");
            }
            if (!without.equals(refWithout)) {
                failures.add(p + ": UCFS without the derived new edges != REF on the same input: " + diff(without, refWithout));
            }
            if (kinds.get(NewKind.OTHER) != 0) {
                failures.add(p + ": " + kinds.get(NewKind.OTHER) + " new edges of no known class");
            }
            if (zero.size() != 1 || !zero.iterator().next().equals(pta.getRootNode().base())) {
                failures.add(p + ": expected exactly the ROOT object with context number 0, got " + zero);
            }
            if (ucfs.isEmpty()) {
                failures.add(p + ": empty UCFS answer");
            }
        }
        System.out.println("E3UcfsPointsToTest total: programs=" + PROGRAMS.length + " ucfsPairs=" + total[0]
                + " sparkPairs=" + total[1] + " missing=" + total[2] + " extra=" + total[3] + " extraR4b=" + total[4]
                + " extraR1=" + total[5] + " extraR2=" + total[6] + " extraR5=" + total[7] + " newEdges=" + total[8]
                + " derivedNew=" + total[9] + " derivedNewIntoThis=" + total[10] + " pairsWithoutDerivedNew=" + total[11]);
        assertTrue(String.join("\n", failures), failures.isEmpty());
    }

    /** Assert.mayAlias/notAlias(a, b) calls with two locals in reachable methods of the program. */
    record AliasQuery(SootMethod m, Local a, Local b, boolean mayAlias) {
    }

    static List<AliasQuery> queries(PTA pta) {
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

    static boolean ucfsAlias(PTA pta, Map<Node, Set<AllocNode>> ucfs, AliasQuery q) {
        Set<AllocNode> a = ucfs.getOrDefault(pta.getPag().findLocalVarNode(q.a()), Set.of());
        Set<AllocNode> b = ucfs.getOrDefault(pta.getPag().findLocalVarNode(q.b()), Set.of());
        return a.stream().anyMatch(b::contains);
    }

    /**
     * Receiver2This: B.foo has mayAlias(this, o), A.foo has notAlias(this, o) (source comments).
     * With the receiver binding of the analysis (E3.md D2, main mode) UCFS answers both as the
     * source says; pts(this) here is the input taken from Spark (E3.md D1).
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
