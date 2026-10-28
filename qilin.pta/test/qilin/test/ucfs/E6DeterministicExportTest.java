package qilin.test.ucfs;

import org.junit.Test;
import qilin.core.PTA;
import qilin.core.PTAScene;
import qilin.core.pag.AllocNode;
import qilin.core.pag.FieldRefNode;
import qilin.core.pag.LocalVarNode;
import qilin.core.pag.Node;
import qilin.core.pag.PAG;
import qilin.core.pag.VarNode;
import qilin.test.util.JunitTests;
import qilin.ucfs.LabeledEdge;
import qilin.ucfs.idr.IdrCalls;
import qilin.ucfs.idr.IdrExport;
import qilin.ucfs.idr.IdrGraph;
import qilin.ucfs.idr.IdrVertex;
import qilin.ucfs.idr.Layer;
import soot.Local;
import soot.SootMethod;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

/**
 * E6-S4b: the export of IdrExport does not depend on the order in which it reads the PAG, the call graph
 * and the exception records (docs/ai/tickets/E6-S4b.md; finding of verify-E6-S5: the home of the merged
 * heap of -mh was chosen by the order of a hash map, and the CS numbers of CsFacts changed between runs of
 * the JVM). Not an acceptance test of the plan: the implementer's own check.
 *
 * <p>Within one JVM the PAG maps of Qilin iterate in one order, so the test uses the seam
 * {@code IdrExport.export(pta, calls, shuffle)}, which shuffles the PAG edges, call edges and exception
 * assignments it read with a given Random before it orders them. The graph (edges with their labels,
 * vertices, fields, sites, counters) must equal the one of {@code export(pta, calls)} for every seed.
 * The run across JVMs is scripts/cflidr/determinism.sh.
 *
 * <p>Home of an object without a method (IdrExport.homes): the method with the most of its local targets,
 * on a tie the one with the least SootMethod.getSignature(). Program qilin.microben.context.hyb.Hyb2 with an
 * injected object without a method (PAG.makeAllocNode(..., null) and PAG.addEdge, as Solver.addToPAG adds
 * the edges of the MergedNewExpr of -mh) whose targets are locals of foo (a, p) and of main (a1, a2), added
 * in either order: on a tie the targets in the method of the greater signature are context-insensitive
 * (F_IN vertex) and those in the home are not; with more targets in one method, that method is the home
 * whatever its signature.
 */
public class E6DeterministicExportTest extends JunitTests {
    private static final long[] SEEDS = {1, 2, 3, 17, 2026};

    @Test
    public void tieOfOneTargetEach() {
        checkHome(new String[]{"a"}, new String[]{"a1"});
    }

    @Test
    public void tieOfTwoTargetsEach() {
        checkHome(new String[]{"a", "p"}, new String[]{"a1", "a2"});
    }

    @Test
    public void moreTargetsInOneMethod() {
        checkHome(new String[]{"a"}, new String[]{"a1", "a2"});
    }

    /**
     * On programs of E3 and E6 with -mh (as JunitTests), in the three modes: the export of shuffled inputs
     * equals the export of the inputs as read, and no two nodes or sites have one key (order-ties).
     * ExceptionChain has exception assignments and two objects of a MergedNewExpr (ArithmeticException,
     * ClassCastException).
     */
    @Test
    public void shuffledInputsGiveTheSameGraphInEveryMode() {
        String[] programs = {E6Reference.CONTEXT + "hyb.Hyb2", E6Reference.CONTEXT + "cfa.CFA2k",
                E6Reference.CONTEXT + "obj.OBJ2k1", E6Reference.CORE + "field.InstanceLoad",
                E6Reference.CORE + "natives.PrivilegedActions2", E6Reference.CORE + "exception.ExceptionChain"};
        for (String p : programs) {
            PTAScene.junitReset();
            PTA pta = run(p, "insens");
            for (IdrCalls calls : IdrCalls.values()) {
                IdrGraph g = IdrExport.export(pta, calls);
                assertEquals(p + " " + calls + ": order-ties", 0, (int) g.getCounters().get("order-ties"));
                for (long seed : SEEDS) {
                    assertSameGraph(p + " " + calls + " seed " + seed, g, IdrExport.export(pta, calls, new Random(seed)));
                }
                System.out.println("E6DeterministicExportTest " + p + " " + calls + ": " + g.getCounters());
            }
        }
    }

    private void checkHome(String[] inFoo, String[] inMain) {
        List<String> dots = new ArrayList<>();
        for (boolean fooFirst : new boolean[]{true, false}) {
            PTAScene.junitReset();
            PTA pta = run(E6Reference.CONTEXT + "hyb.Hyb2", "insens");
            PAG pag = pta.getPag();
            List<Node> foo = new ArrayList<>();
            List<Node> main = new ArrayList<>();
            for (String name : inFoo) {
                foo.add(local(pag, "foo", name));
            }
            for (String name : inMain) {
                main.add(local(pag, "main", name));
            }
            SootMethod fooM = ((LocalVarNode) foo.get(0)).getMethod();
            SootMethod mainM = ((LocalVarNode) main.get(0)).getMethod();
            AllocNode merged = pag.makeAllocNode("E6DeterministicExportTest-merged",
                    ((VarNode) foo.get(0)).getType(), null);
            List<Node> order = new ArrayList<>(fooFirst ? foo : main);
            order.addAll(fooFirst ? main : foo);
            for (Node v : order) {
                pag.addEdge(merged, v);
            }

            boolean fooHome = foo.size() != main.size() ? foo.size() > main.size()
                    : fooM.getSignature().compareTo(mainM.getSignature()) < 0;
            IdrGraph g = IdrExport.export(pta, IdrCalls.CS);
            String what = "Hyb2 + object without a method -> foo " + List.of(inFoo) + ", main " + List.of(inMain)
                    + (fooFirst ? ", foo first" : ", main first");
            System.out.println("E6DeterministicExportTest " + what + ": home " + (fooHome ? fooM : mainM)
                    + " " + g.getCounters());
            for (Node v : foo) {
                assertEquals(what + ": " + v + " is context-insensitive", !fooHome, isJump(g, v));
            }
            for (Node v : main) {
                assertEquals(what + ": " + v + " is context-insensitive", fooHome, isJump(g, v));
            }
            assertEquals(what + ": methodless-new-targets", fooHome ? main.size() : foo.size(),
                    (int) g.getCounters().get("methodless-new-targets"));
            assertEquals(what + ": order-ties", 0, (int) g.getCounters().get("order-ties"));
            for (long seed : SEEDS) {
                assertSameGraph(what + ", seed " + seed, g, IdrExport.export(pta, IdrCalls.CS, new Random(seed)));
            }
            dots.add(dot(g));
        }
        assertEquals("the graph does not depend on the order the edges of the object were added", dots.get(0), dots.get(1));
    }

    private static boolean isJump(IdrGraph g, Node v) {
        return g.idOf(new IdrVertex(E6Reference.ci(v), Layer.F_IN)) >= 0;
    }

    private static void assertSameGraph(String what, IdrGraph want, IdrGraph got) {
        assertEquals(what + ": vertices", want.getVertices(), got.getVertices());
        assertEquals(what + ": fields", want.getFields(), got.getFields());
        assertEquals(what + ": sites", want.getSites(), got.getSites());
        assertEquals(what + ": edges", want.getEdges(), got.getEdges());
        assertEquals(what + ": counters", want.getCounters(), got.getCounters());
    }

    /** The lines of graph.dot (IdrExport.writeDot) and the sites. */
    private static String dot(IdrGraph g) {
        StringBuilder sb = new StringBuilder();
        for (LabeledEdge e : g.getEdges()) {
            sb.append(e.getFrom()).append("->").append(e.getTo()).append("[label=\"").append(e.getLabel()).append("\"];\n");
        }
        for (soot.Unit s : g.getSites()) {
            sb.append(s).append('\n');
        }
        return sb.toString();
    }

    /** The CI node of the local [name] of the Hyb2 method [method] that is a base or value of a store or load. */
    private static Node local(PAG pag, String method, String name) {
        for (Map.Entry<FieldRefNode, Set<VarNode>> e : pag.getStoreInv().entrySet()) {
            if (isLocal(e.getKey().getBase(), method, name)) {
                return E6Reference.ci(e.getKey().getBase());
            }
            for (VarNode y : e.getValue()) {
                if (isLocal(y, method, name)) {
                    return E6Reference.ci(y);
                }
            }
        }
        for (Map.Entry<FieldRefNode, Set<VarNode>> e : pag.getLoad().entrySet()) {
            if (isLocal(e.getKey().getBase(), method, name)) {
                return E6Reference.ci(e.getKey().getBase());
            }
        }
        throw new AssertionError("Hyb2 has no local " + name + " of " + method + " in a store or load");
    }

    private static boolean isLocal(Node n, String method, String name) {
        return E6Reference.ci(n) instanceof LocalVarNode lv && lv.getMethod().getName().equals(method)
                && lv.getVariable() instanceof Local l && l.getName().equals(name);
    }
}
