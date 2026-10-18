package qilin.test.ucfs;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import org.junit.Test;
import qilin.core.PTA;
import qilin.core.PTAScene;
import qilin.core.pag.AllocNode;
import qilin.core.pag.ArrayElement;
import qilin.core.pag.ContextAllocNode;
import qilin.core.pag.ContextField;
import qilin.core.pag.ContextVarNode;
import qilin.core.pag.FieldRefNode;
import qilin.core.pag.GlobalVarNode;
import qilin.core.pag.LocalVarNode;
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
import soot.SootField;
import soot.SootMethod;
import soot.jimple.spark.pag.SparkField;

/**
 * E3-S1 acceptance check (docs/ai/tickets/E3-S1.md): PagExport.export(pta) turns the global PAG
 * of a finished analysis (Spark, insens) into the labeled graph handed to UCFS (E3.md D1-D4):
 * <ul>
 *   <li>vertices = context-insensitive nodes: LocalVarNode, GlobalVarNode, AllocNode (not a
 *       context node, not a FieldRefNode, not a ContextField); dense ids 0..n-1;</li>
 *   <li>edges with an end in a ContextField (o.f, derived by Spark from points-to sets) are
 *       dropped; the edges of the four maps are kept, projected to the CI nodes (some new edges of
 *       the maps are made by the solver too, e.g. receiver object -> this; E3.md D1, E3-S3):
 *       NEW o -> v as "new", ASSIGN u -> v as "assign", STORE y -> x.f as y -"store_i"-> x,
 *       LOAD x.f -> z as x -"load_i"-> z, i = dense index of the field f;</li>
 *   <li>every edge also reversed with the label + "_bar"; no duplicates.</li>
 * </ul>
 * Oracles, none a copy of the implementation: (1) the same graph rebuilt from the INVERSE maps of
 * the PAG enumerated through the node numberer; (2) structural properties of ids and labels;
 * (3) facts of small qilin.microben programs derived by hand from their source (each test).
 */
public class E3PagExportTest extends JunitTests {

    private static final String P = "qilin.microben.core.";

    /** A labeled edge over PAG nodes before ids: field == null for new/assign. */
    private record NodeEdge(Node from, String kind, SparkField field, Node to) {
    }

    private static Node ci(Node n) {
        if (n instanceof VarNode v) {
            return v.base();
        }
        if (n instanceof AllocNode a) {
            return a.base();
        }
        throw new AssertionError("unexpected node " + n);
    }

    /** Oracle 1: the expected forward edges, from the inverse maps (keyed by target; store by source). */
    private static Set<NodeEdge> expectedForward(PAG pag) {
        Set<NodeEdge> edges = new HashSet<>();
        for (ValNode v : pag.getValNodeNumberer()) {
            boolean vField = v instanceof ContextField;
            for (ValNode src : pag.simpleInvLookup(v)) {
                if (!vField && !(src instanceof ContextField)) {
                    edges.add(new NodeEdge(ci(src), "assign", null, ci(v)));
                }
            }
            if (v instanceof VarNode var) {
                for (AllocNode heap : pag.allocInvLookup(var)) {
                    edges.add(new NodeEdge(ci(heap), "new", null, ci(var)));
                }
                for (FieldRefNode fr : pag.loadInvLookup(var)) {
                    edges.add(new NodeEdge(ci(fr.getBase()), "load", fr.getField(), ci(var)));
                }
                for (FieldRefNode fr : pag.storeLookup(var)) {
                    edges.add(new NodeEdge(ci(var), "store", fr.getField(), ci(fr.getBase())));
                }
            }
        }
        return edges;
    }

    private static String label(UcfsGraph g, NodeEdge e) {
        switch (e.kind()) {
            case "new":
                return PtLabels.NEW;
            case "assign":
                return PtLabels.ASSIGN;
            case "store":
                return PtLabels.store(g.fieldIndex(e.field()));
            default:
                return PtLabels.load(g.fieldIndex(e.field()));
        }
    }

    private static boolean isCiVertex(Node n) {
        return (n instanceof LocalVarNode || n instanceof GlobalVarNode || n instanceof AllocNode)
                && !(n instanceof ContextAllocNode) && !(n instanceof ContextVarNode);
    }

    /** Runs Spark, exports, checks the oracles valid for every program; returns the graph. */
    private UcfsGraph exportAndCheck(String mainClass) {
        PTA pta = run(mainClass, "insens");
        UcfsGraph g = PagExport.export(pta);
        int n = g.getVertices().size();
        System.out.println("E3PagExportTest " + mainClass + ": vertices=" + n + " edges=" + g.getEdges().size()
                + " fields=" + g.getFields().size());

        // ids: dense, round trip, CI node types, every vertex on some edge
        assertEquals("vertex list has no duplicates", n, new HashSet<>(g.getVertices()).size());
        for (int i = 0; i < n; i++) {
            Node node = g.nodeOf(i);
            assertTrue("vertex " + i + " must be a CI LocalVarNode/GlobalVarNode/AllocNode: " + node, isCiVertex(node));
            assertEquals("vertexOf(nodeOf(i)) == i", i, g.vertexOf(node));
        }
        Set<Integer> onEdges = new HashSet<>();
        for (LabeledEdge e : g.getEdges()) {
            assertTrue("edge ends are vertex ids: " + e, e.getFrom() >= 0 && e.getFrom() < n && e.getTo() >= 0 && e.getTo() < n);
            onEdges.add(e.getFrom());
            onEdges.add(e.getTo());
        }
        assertEquals("every vertex lies on an edge", n, onEdges.size());
        int k = g.getFields().size();
        assertEquals("field list has no duplicates", k, new HashSet<>(g.getFields()).size());
        for (int i = 0; i < k; i++) {
            assertEquals("fieldIndex(fields[i]) == i", i, g.fieldIndex(g.getFields().get(i)));
        }
        assertEquals("edge list has no duplicates", g.getEdges().size(), new HashSet<>(g.getEdges()).size());

        // oracle 1: equal to the graph rebuilt from the inverse maps, with the reversed edges
        Set<LabeledEdge> expected = new HashSet<>();
        Set<SparkField> usedFields = new HashSet<>();
        for (NodeEdge e : expectedForward(pta.getPag())) {
            int from = g.vertexOf(e.from());
            int to = g.vertexOf(e.to());
            assertTrue("node of an expected edge has no vertex id: " + e, from >= 0 && to >= 0);
            if (e.field() != null) {
                assertTrue("field of an expected edge has no index: " + e, g.fieldIndex(e.field()) >= 0);
                usedFields.add(e.field());
            }
            String l = label(g, e);
            expected.add(new LabeledEdge(from, l, to));
            expected.add(new LabeledEdge(to, PtLabels.bar(l), from));
        }
        Set<LabeledEdge> actual = new HashSet<>(g.getEdges());
        Set<LabeledEdge> missing = new HashSet<>(expected);
        missing.removeAll(actual);
        Set<LabeledEdge> extra = new HashSet<>(actual);
        extra.removeAll(expected);
        assertTrue("edges missing from the export: " + missing, missing.isEmpty());
        assertTrue("unexpected edges in the export: " + extra, extra.isEmpty());
        assertEquals("every exported field is used by a load or store edge", usedFields, new HashSet<>(g.getFields()));
        return g;
    }

    private static SootMethod method(String signature) {
        return PTAScene.v().getMethod(signature);
    }

    private static boolean isLocalOf(Node n, SootMethod m) {
        return n instanceof LocalVarNode lv && lv.getMethod().equals(m);
    }

    private static boolean isParmOf(Node n, SootMethod m, int index) {
        return n instanceof LocalVarNode lv && lv.getMethod().equals(m) && lv.getVariable() instanceof Parm p
                && p.getIndex() == index;
    }

    private static List<LabeledEdge> edges(UcfsGraph g, String label) {
        return g.getEdges().stream().filter(e -> e.getLabel().equals(label)).collect(Collectors.toList());
    }

    private static int field(UcfsGraph g, String cls, String name) {
        for (SparkField f : g.getFields()) {
            if (f instanceof SootField sf && sf.getName().equals(name) && sf.getDeclaringClass().getName().equals(cls)) {
                return g.fieldIndex(f);
            }
        }
        throw new AssertionError("field " + cls + "." + name + " not in the export: " + g.getFields());
    }

    /** Sources of edges labeled {@code label} into vertex {@code to}. */
    private static Set<Node> sourcesInto(UcfsGraph g, String label, int to) {
        return g.getEdges().stream().filter(e -> e.getLabel().equals(label) && e.getTo() == to)
                .map(e -> g.nodeOf(e.getFrom())).collect(Collectors.toSet());
    }

    /**
     * FieldSensitivity1: constructor {@code A(Object o1, Object o2) { this.f = o1; this.g = o2; }}.
     * Two store edges in A.&lt;init&gt;, with different field indices (f vs g), both into the local
     * holding {@code this}; the source of store_f is the local of parameter 0, of store_g the
     * local of parameter 1. Main reads {@code a.f} and {@code a.g}: load edges from main's local
     * {@code a} with the same two indices.
     */
    @Test
    public void fieldSensitivity1() {
        String cls = P + "field.FieldSensitivity1$A";
        UcfsGraph g = exportAndCheck(P + "field.FieldSensitivity1");
        SootMethod init = method("<" + cls + ": void <init>(java.lang.Object,java.lang.Object)>");
        SootMethod main = method("<" + P + "field.FieldSensitivity1: void main(java.lang.String[])>");
        int f = field(g, cls, "f");
        int gg = field(g, cls, "g");
        assertNotEquals("fields f and g need different indices", f, gg);
        List<LabeledEdge> storeF = edges(g, PtLabels.store(f));
        List<LabeledEdge> storeG = edges(g, PtLabels.store(gg));
        assertEquals("one store to f: " + storeF, 1, storeF.size());
        assertEquals("one store to g: " + storeG, 1, storeG.size());
        int base = storeF.get(0).getTo();
        assertEquals("both stores go into the same base local (this)", base, storeG.get(0).getTo());
        assertTrue("store base is a local of A.<init>", isLocalOf(g.nodeOf(base), init));
        assertTrue("the base local gets this: assign from the THIS parameter",
                sourcesInto(g, PtLabels.ASSIGN, base).stream().anyMatch(s -> isLocalOf(s, init) && ((LocalVarNode) s).isThis()));
        assertTrue("store_f stores the local of parameter 0",
                sourcesInto(g, PtLabels.ASSIGN, storeF.get(0).getFrom()).stream().anyMatch(s -> isParmOf(s, init, 0)));
        assertTrue("store_g stores the local of parameter 1",
                sourcesInto(g, PtLabels.ASSIGN, storeG.get(0).getFrom()).stream().anyMatch(s -> isParmOf(s, init, 1)));
        assertTrue("main loads a.f", edges(g, PtLabels.load(f)).stream().anyMatch(e -> isLocalOf(g.nodeOf(e.getFrom()), main)));
        assertTrue("main loads a.g", edges(g, PtLabels.load(gg)).stream().anyMatch(e -> isLocalOf(g.nodeOf(e.getFrom()), main)));
    }

    /**
     * Receiver2This: {@code a1 = new A(); a2 = new B(); a1.foo(a2); test(a1, a2); test(a2, a2);}
     * with {@code test(A a, Object b) { a.foo(b); }} and B overriding foo. In the main export mode
     * the receiver binding comes from the dispatch of the analysis (E3.md D2): new edges object ->
     * this, made by the solver from the points-to set of the receiver (so pts(this) is Spark's
     * answer, E3.md D1); this of A.foo gets only the A object, this of B.foo only the B object, and
     * no assign edge enters either this (there is no edge from the receiver variable {@code a} of
     * test to this). The second mode, receiver variable -> this along the call graph, is E3-S3b.
     */
    @Test
    public void receiver2This() {
        String cls = P + "assign.Receiver2This";
        UcfsGraph g = exportAndCheck(cls);
        for (String[] c : new String[][]{{"A", cls + "$A"}, {"B", cls + "$B"}}) {
            SootMethod foo = method("<" + cls + "$" + c[0] + ": void foo(java.lang.Object)>");
            int thisV = -1;
            for (int i = 0; i < g.getVertices().size(); i++) {
                if (isParmOf(g.nodeOf(i), foo, -1)) {
                    thisV = i;
                }
            }
            assertTrue("this of " + foo + " is a vertex", thisV >= 0);
            Set<Node> objs = sourcesInto(g, PtLabels.NEW, thisV);
            assertEquals("one object reaches this of " + foo + ": " + objs, 1, objs.size());
            assertEquals(c[1], objs.iterator().next().getType().toString());
            assertTrue("no assign edge into this of " + foo, sourcesInto(g, PtLabels.ASSIGN, thisV).isEmpty());
        }
    }

    /**
     * ArrayIndex: {@code t = new Object[5]; t[0] = o1; t[1] = o2;}. All elements are the single
     * field ArrayElement; both stores go into t with its index.
     */
    @Test
    public void arrayIndex() {
        UcfsGraph g = exportAndCheck(P + "array.ArrayIndex");
        SootMethod main = method("<" + P + "array.ArrayIndex: void main(java.lang.String[])>");
        int arr = g.fieldIndex(ArrayElement.v());
        assertTrue("ArrayElement is an exported field", arr >= 0);
        List<LabeledEdge> st = edges(g, PtLabels.store(arr)).stream()
                .filter(e -> isLocalOf(g.nodeOf(e.getTo()), main)).collect(Collectors.toList());
        assertEquals("two array stores in main: " + st, 2, st.size());
        assertEquals("into the same array local", st.get(0).getTo(), st.get(1).getTo());
        assertNotEquals("from two different locals", st.get(0).getFrom(), st.get(1).getFrom());
    }

    /**
     * StaticStore: {@code static Object a; ... a = o;}. A static field is the GlobalVarNode of the
     * field: an assign edge from main's local into it, and no exported field is static.
     */
    @Test
    public void staticStore() {
        String cls = P + "global.StaticStore";
        UcfsGraph g = exportAndCheck(cls);
        SootMethod main = method("<" + cls + ": void main(java.lang.String[])>");
        List<Integer> globals = new ArrayList<>();
        for (int i = 0; i < g.getVertices().size(); i++) {
            if (g.nodeOf(i) instanceof GlobalVarNode gv && gv.getVariable() instanceof SootField sf
                    && sf.getName().equals("a") && sf.getDeclaringClass().getName().equals(cls)) {
                globals.add(i);
            }
        }
        assertEquals("one vertex for the static field a", 1, globals.size());
        assertTrue("assign from a local of main into the static field",
                sourcesInto(g, PtLabels.ASSIGN, globals.get(0)).stream().anyMatch(s -> isLocalOf(s, main)));
        assertFalse("static fields are not load/store fields",
                g.getFields().stream().anyMatch(f -> f instanceof SootField sf && sf.isStatic()));
    }

    /**
     * InstanceStore: {@code i = new InstanceStore(); o = new Object(); i.a = o;}: the edge
     * o -store_a-> i between two locals of main, and i gets the InstanceStore object by new.
     * The ContextField (that object).a of the global PAG is not a vertex.
     */
    @Test
    public void instanceStore() {
        String cls = P + "field.InstanceStore";
        UcfsGraph g = exportAndCheck(cls);
        SootMethod main = method("<" + cls + ": void main(java.lang.String[])>");
        int a = field(g, cls, "a");
        List<LabeledEdge> st = edges(g, PtLabels.store(a));
        assertEquals("one store to a: " + st, 1, st.size());
        assertTrue("from a local of main", isLocalOf(g.nodeOf(st.get(0).getFrom()), main));
        assertTrue("into a local of main", isLocalOf(g.nodeOf(st.get(0).getTo()), main));
        Set<Node> objs = sourcesInto(g, PtLabels.NEW, st.get(0).getTo());
        assertTrue("the base i gets the InstanceStore object: " + objs,
                objs.stream().anyMatch(o -> o.getType().toString().equals(cls)));
        assertEquals("one reversed edge for the store", 1, edges(g, PtLabels.bar(PtLabels.store(a))).size());
    }
}
