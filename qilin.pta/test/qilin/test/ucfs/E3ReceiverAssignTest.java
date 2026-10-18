package qilin.test.ucfs;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.Test;
import qilin.core.PTA;
import qilin.core.PTAScene;
import qilin.core.PointsToAnalysis;
import qilin.core.pag.AllocNode;
import qilin.core.pag.LocalVarNode;
import qilin.core.pag.Node;
import qilin.core.pag.Parm;
import qilin.test.util.JunitTests;
import qilin.ucfs.LabeledEdge;
import qilin.ucfs.PagExport;
import qilin.ucfs.ReceiverBinding;
import qilin.ucfs.UcfsGraph;
import qilin.ucfs.UcfsPointsTo;
import qilin.ucfs.grammar.PointsToGrammar;
import soot.SootMethod;
import soot.jimple.InstanceInvokeExpr;
import soot.jimple.Stmt;
import soot.jimple.toolkits.callgraph.Edge;

/**
 * E3-S3b acceptance check (docs/ai/tickets/E3-S3b.md): the second export mode
 * PagExport.export(pta, ReceiverBinding.CALL_GRAPH) without the "new" edges receiver object ->
 * this that the solver of Spark made from points-to sets (CallGraphBuilder.addVirtualEdge, E3.md
 * B1/D2). Instead, an "assign" edge receiver variable -> this for every edge of Spark's call graph
 * out of an instance call. UCFS then computes pts(this) itself; the call graph is still Spark's
 * (class R3), the exception edges are still Spark's (counted, E3.md D1).
 *
 * <p>Oracles (computed here, not by PagExport):
 * <ol>
 *   <li>the graph equals the one the test builds: the PAG maps (as in E3-S1/S3) without the new
 *       edges into a this node except ROOT -> this of the fake main method, plus receiver variable
 *       -> this taken from Soot's CI call graph of the analysis and the Jimple base of each instance
 *       invoke (not from CallGraphBuilder's receiver map that an implementation may use);</li>
 *   <li>no new edge into a this node is left except the ROOT one (derivedNewIntoThis = 0);</li>
 *   <li>UCFS called directly on that graph = Andersen without filters on the same input (REF2);
 *       UcfsPointsTo.solve(graph, PointsToGrammar) returns the same map;</li>
 *   <li>soundness: every Spark points-to set is a subset of the UCFS set; the answer of the main
 *       mode is a subset too, and the growth is printed (all of it comes from binding this without
 *       Spark's dispatch filter, class R3);</li>
 *   <li>hand facts of Receiver2This and every Assert.mayAlias of the 43 programs.</li>
 * </ol>
 */
public class E3ReceiverAssignTest extends JunitTests {

    private static final String P = E3UcfsPointsToTest.P;

    /** receiver variable -> this of the callee, from Soot's CI call graph and the Jimple invoke base. */
    static List<Node[]> receiverAssigns(PTA pta) {
        List<Node[]> out = new ArrayList<>();
        Set<List<Node>> seen = new HashSet<>();
        for (Edge e : pta.getCallGraph()) {
            Stmt s = e.srcStmt();
            if (s == null || !s.containsInvokeExpr() || !(s.getInvokeExpr() instanceof InstanceInvokeExpr iie)) {
                continue;
            }
            SootMethod callee = e.tgt();
            if (callee.isStatic()) {
                continue;
            }
            LocalVarNode recv = pta.getPag().findLocalVarNode(iie.getBase());
            LocalVarNode thisNode = pta.getPag().findLocalVarNode(new Parm(callee, PointsToAnalysis.THIS_NODE));
            assertNotNull("receiver variable of " + s, recv);
            assertNotNull("this of " + callee, thisNode);
            if (seen.add(List.of(recv, thisNode))) {
                out.add(new Node[]{recv, thisNode});
            }
        }
        return out;
    }

    /** The PAG edges of the second mode, built by the test. */
    static E3UcfsPointsToTest.Edges expectedEdges(PTA pta) {
        AllocNode root = pta.getRootNode().base();
        return new E3UcfsPointsToTest.Edges(pta.getPag()).with(
                (o, v) -> v instanceof LocalVarNode lv && lv.isThis() && !o.equals(root), receiverAssigns(pta));
    }

    @Test
    public void callGraphBindingAllPrograms() {
        List<String> failures = new ArrayList<>();
        int[] total = new int[8];
        for (String p : E3UcfsPointsToTest.PROGRAMS) {
            PTAScene.junitReset();
            PTA pta = run(P + p, "insens");
            UcfsGraph g1 = PagExport.export(pta);
            UcfsGraph g2 = PagExport.export(pta, ReceiverBinding.CALL_GRAPH);
            E3UcfsPointsToTest.Edges exp = expectedEdges(pta);

            // 1: the graph equals the one built by the test
            Set<LabeledEdge> expected = exp.labeled(g2);
            Set<LabeledEdge> actual = new HashSet<>(g2.getEdges());
            Set<LabeledEdge> missingEdges = new HashSet<>(expected);
            missingEdges.removeAll(actual);
            Set<LabeledEdge> extraEdges = new HashSet<>(actual);
            extraEdges.removeAll(expected);
            if (!missingEdges.isEmpty() || !extraEdges.isEmpty() || actual.size() != g2.getEdges().size()) {
                failures.add(p + ": export (CALL_GRAPH) != graph built by the test: missing " + missingEdges.size()
                        + " " + first(missingEdges) + ", unexpected " + extraEdges.size() + " " + first(extraEdges));
            }
            // 2: no derived new edge into this is left
            Map<E3UcfsPointsToTest.NewKind, Integer> kinds = E3UcfsPointsToTest.newKinds(pta, g2, null);
            int intoThis = kinds.get(E3UcfsPointsToTest.NewKind.RECEIVER);
            if (intoThis != 0) {
                failures.add(p + ": " + intoThis + " new edges object -> this left in the CALL_GRAPH export");
            }
            if (kinds.get(E3UcfsPointsToTest.NewKind.OTHER) != 0) {
                failures.add(p + ": new edges of no known class in the CALL_GRAPH export");
            }
            // 3: UCFS = REF2 on the same input; solve(graph, grammar) = UCFS
            Map<Node, Set<AllocNode>> ucfs2 = E3UcfsPointsToTest.ucfsDirect(g2, g2.getEdges());
            Map<Node, Set<AllocNode>> ref2 = E3UcfsPointsToTest.andersen(exp, E3UcfsPointsToTest.Filters.NONE, true);
            Map<Node, Set<AllocNode>> solved = E3UcfsPointsToTest.normalize(
                    UcfsPointsTo.solve(g2, new PointsToGrammar(g2.getFields().size())));
            if (!ucfs2.equals(ref2)) {
                failures.add(p + ": UCFS (CALL_GRAPH) != REF2: " + E3UcfsPointsToTest.diff(ucfs2, ref2));
            }
            if (!solved.equals(ucfs2)) {
                failures.add(p + ": UcfsPointsTo.solve(graph, grammar) != UCFS called by the test");
            }
            // 4: soundness and growth
            Map<Node, Set<AllocNode>> sp = E3UcfsPointsToTest.spark(pta, E3UcfsPointsToTest.ciVars(pta.getPag()));
            Map<Node, Set<AllocNode>> ucfs1 = E3UcfsPointsToTest.ucfsDirect(g1, g1.getEdges());
            int missing = E3UcfsPointsToTest.minus(sp, ucfs2).size();
            int lostFromMain = E3UcfsPointsToTest.minus(ucfs1, ucfs2).size();
            int growth = E3UcfsPointsToTest.minus(ucfs2, ucfs1).size();
            if (missing != 0) {
                failures.add(p + ": " + missing + " Spark pairs missing from UCFS (CALL_GRAPH)");
            }
            if (lostFromMain != 0) {
                failures.add(p + ": " + lostFromMain + " pairs of the main mode missing from the CALL_GRAPH mode");
            }
            int receiverAssign = exp.assign.size() - new E3UcfsPointsToTest.Edges(pta.getPag()).assign.size();
            int[] row = {E3UcfsPointsToTest.pairs(ucfs1), E3UcfsPointsToTest.pairs(ucfs2), growth,
                    E3UcfsPointsToTest.pairs(sp), missing, receiverAssign, intoThis,
                    kinds.get(E3UcfsPointsToTest.NewKind.EXCEPTION)};
            for (int i = 0; i < row.length; i++) {
                total[i] += row[i];
            }
            System.out.println("E3ReceiverAssignTest " + p + ": edges1=" + g1.getEdges().size() + " edges2="
                    + g2.getEdges().size() + " receiverAssign=" + receiverAssign + " derivedNewIntoThis=" + intoThis
                    + " derivedNewException=" + row[7] + " derivedNewFinalizer=" + kinds.get(E3UcfsPointsToTest.NewKind.FINALIZER)
                    + " ucfsPairs1=" + row[0] + " ucfsPairs2=" + row[1] + " growthR3=" + growth + " sparkPairs=" + row[3]
                    + " missing=" + missing);
        }
        System.out.println("E3ReceiverAssignTest total: programs=" + E3UcfsPointsToTest.PROGRAMS.length
                + " ucfsPairs1=" + total[0] + " ucfsPairs2=" + total[1] + " growthR3=" + total[2] + " sparkPairs=" + total[3]
                + " missing=" + total[4] + " receiverAssign=" + total[5] + " derivedNewIntoThis=" + total[6]
                + " derivedNewException=" + total[7]);
        assertTrue(String.join("\n", failures), failures.isEmpty());
    }

    private static String first(Set<LabeledEdge> s) {
        return s.stream().limit(3).toList().toString();
    }

    /**
     * Receiver2This: {@code a1 = new A(); a2 = new B(); a1.foo(a2); test(a1, a2); test(a2, a2);}
     * with {@code test(A a, Object b) { a.foo(b); }}, B overriding foo, A.foo asserting
     * notAlias(this, o), B.foo asserting mayAlias(this, o). Derived by hand for the CALL_GRAPH mode:
     * a in test points to the A and the B object; Spark's call graph has a.foo(b) -> A.foo and
     * -> B.foo; so this of A.foo gets both objects (Spark's dispatch would give only A). o of A.foo
     * gets a2 from a1.foo(a2), i.e. the B object. Hence UCFS answers "may alias" for A.foo's
     * notAlias (lost precision of class R3, receiver bound without the dispatch filter), and B.foo's
     * mayAlias still holds.
     */
    @Test
    public void receiver2ThisCallGraphBinding() {
        PTAScene.junitReset();
        String cls = P + "assign.Receiver2This";
        PTA pta = run(cls, "insens");
        UcfsGraph g2 = PagExport.export(pta, ReceiverBinding.CALL_GRAPH);
        Map<Node, Set<AllocNode>> ucfs = E3UcfsPointsToTest.normalize(
                UcfsPointsTo.solve(g2, new PointsToGrammar(g2.getFields().size())));
        SootMethod aFoo = PTAScene.v().getMethod("<" + cls + "$A: void foo(java.lang.Object)>");
        LocalVarNode thisA = pta.getPag().findLocalVarNode(new Parm(aFoo, PointsToAnalysis.THIS_NODE));
        Set<String> types = new HashSet<>();
        for (AllocNode o : ucfs.getOrDefault(thisA, Set.of())) {
            types.add(o.getType().toString());
        }
        assertEquals("this of A.foo gets the A and the B object", Set.of(cls + "$A", cls + "$B"), types);
        List<E3UcfsPointsToTest.AliasQuery> qs = E3UcfsPointsToTest.queries(pta);
        assertEquals("Receiver2This has 2 alias assertions: " + qs, 2, qs.size());
        for (E3UcfsPointsToTest.AliasQuery q : qs) {
            assertTrue((q.mayAlias() ? "B.foo mayAlias holds" : "A.foo notAlias becomes may-alias (R3)") + ": " + q,
                    E3UcfsPointsToTest.ucfsAlias(pta, ucfs, q));
        }
    }

    /** Every mayAlias assertion with two locals holds under the CALL_GRAPH mode too. */
    @Test
    public void mayAliasAssertionsHoldCallGraphBinding() {
        int n = 0;
        List<String> bad = new ArrayList<>();
        for (String p : E3UcfsPointsToTest.PROGRAMS) {
            PTAScene.junitReset();
            PTA pta = run(P + p, "insens");
            UcfsGraph g2 = PagExport.export(pta, ReceiverBinding.CALL_GRAPH);
            Map<Node, Set<AllocNode>> ucfs = E3UcfsPointsToTest.normalize(
                    UcfsPointsTo.solve(g2, new PointsToGrammar(g2.getFields().size())));
            for (E3UcfsPointsToTest.AliasQuery q : E3UcfsPointsToTest.queries(pta)) {
                if (q.mayAlias()) {
                    n++;
                    if (!E3UcfsPointsToTest.ucfsAlias(pta, ucfs, q)) {
                        bad.add(p + " " + q);
                    }
                }
            }
        }
        System.out.println("E3ReceiverAssignTest mayAlias assertions checked: " + n);
        assertTrue("mayAlias assertions failing under the CALL_GRAPH mode: " + bad, bad.isEmpty());
        assertTrue("the programs have mayAlias assertions", n >= 20);
    }
}
