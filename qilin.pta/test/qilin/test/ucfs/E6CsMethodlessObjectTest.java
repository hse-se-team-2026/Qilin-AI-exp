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
import qilin.ucfs.idr.IdrCalls;
import qilin.ucfs.idr.IdrExport;
import qilin.ucfs.idr.IdrGraph;
import qilin.ucfs.idr.IdrResult;
import qilin.ucfs.idr.IdrSolve;
import qilin.ucfs.idr.IdrVertex;
import qilin.ucfs.idr.Layer;
import soot.Local;

import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

/**
 * E6-S4, iteration 1: an object without a method whose {@code new} edges go into local variables of two
 * methods (ticket E6-S4, Verifier MAJOR-V1 and its probe VerifyE6S4MergedHeapProbe; "Решение лида,
 * итерация 0"). Not an acceptance test of the plan: the implementer's own check of the CS export.
 *
 * <p>With {@code -mh} (as JunitTests and run.py) HeuristicAbstractor merges every StringBuilder,
 * StringBuffer and each Throwable type into one AllocNode of a MergedNewExpr with no method, and
 * Solver.addToPAG adds {@code new} edges from it into the locals of every method that allocated one. A
 * path B(v1) -> OBJ(o) -> F(v2) through such an object goes from the method of v1 to the one of v2 with
 * no call edge, and the CS language (E6Reference.CsModel) keeps the call stack on it.
 *
 * <p>Program qilin.microben.context.hyb.Hyb2: {@code main} calls {@code a1 = b1.foo(o1)},
 * {@code a2 = b2.foo(o2)} and loads {@code v1 = a1.f}; {@code foo(p)} does {@code a = create()} and
 * {@code a.f = p}. After the run the test adds to the PAG an object without a method
 * ({@code PAG.makeAllocNode(..., null)}, as the merged heap) and its {@code new} edges
 * ({@code PAG.addEdge}, as Solver.addToPAG) into {@code a} of foo and into {@code a1} of main. The pair
 * o2 -> v1 is in the CS language only through that object: o2 enters foo at the site of b2.foo (push
 * c2), is stored into a.f, goes backwards from a to the object, forwards into a1 in main with c2 still
 * on the stack, and is loaded into v1. In the graph c2 must be closed somewhere on that path, and foo
 * does not reach main in the call graph, so no END loop of main closes it (027dde6 loses the pair).
 *
 * <p>Two variants, so that the erasure is exercised on either side of the object: one more target in
 * main ({@code a2}) or one more in foo ({@code p}). Expected pairs come from the language
 * (E6Reference.CsModel, bounded enumeration), not from the export: the pair o2 -> v1 must be absent
 * before the injection and present after it, then every bounded pair must be in cfl-idr's
 * over-approximation, under within over within the FIELDS reference.
 */
public class E6CsMethodlessObjectTest extends JunitTests {

    @Test
    public void methodlessObjectWithMoreTargetsInMain() {
        check(false);
    }

    @Test
    public void methodlessObjectWithMoreTargetsInFoo() {
        check(true);
    }

    private void check(boolean moreInFoo) {
        PTAScene.junitReset();
        PTA pta = run(E6Reference.CONTEXT + "hyb.Hyb2", "insens");
        PAG pag = pta.getPag();
        Node aFoo = null, pFoo = null, a1 = null, a2 = null, v1 = null, o2 = null;
        for (Map.Entry<FieldRefNode, Set<VarNode>> e : pag.getStoreInv().entrySet()) {
            if (isLocal(e.getKey().getBase(), "foo", "a")) {
                aFoo = e.getKey().getBase();
                for (VarNode y : e.getValue()) {
                    if (isLocal(y, "foo", "p")) {
                        pFoo = y;
                    }
                }
            }
        }
        for (Map.Entry<FieldRefNode, Set<VarNode>> e : pag.getLoad().entrySet()) {
            if (isLocal(e.getKey().getBase(), "main", "a1")) {
                a1 = e.getKey().getBase();
                for (VarNode z : e.getValue()) {
                    if (isLocal(z, "main", "v1")) {
                        v1 = E6Reference.ci(z);
                    }
                }
            }
            if (isLocal(e.getKey().getBase(), "main", "a2")) {
                a2 = e.getKey().getBase();
            }
        }
        for (E6Reference.CallEdge c : E6Reference.callEdges(pta)) {
            if (c.entry() && isLocal(c.from(), "main", "o2")) {
                o2 = c.from();
            }
        }
        assertTrue("Hyb2 has a and p in foo, a1, a2, v1 = a1.f and o2 in main: " + List.of(String.valueOf(aFoo),
                        String.valueOf(pFoo), String.valueOf(a1), String.valueOf(a2), String.valueOf(v1), String.valueOf(o2)),
                aFoo != null && pFoo != null && a1 != null && a2 != null && v1 != null && o2 != null);
        Map<Node, Set<AllocNode>> refBefore = E6Reference.fieldsReference(pta);
        assertEquals("o2 points to one object", 1, refBefore.get(o2).size());
        AllocNode objO2 = refBefore.get(o2).iterator().next();
        Map<Node, Set<AllocNode>> before = E3UcfsPointsToTest.normalize(
                new E6Reference.CsModel(pta).boundedPairs(E6IdrCsTest.DEPTH, E6IdrCsTest.MAX_STATES));
        assertFalse("without the injected object the CS language has no o2 -> v1",
                before.getOrDefault(v1, Set.of()).contains(objO2));

        AllocNode merged = pag.makeAllocNode("E6CsMethodlessObjectTest-merged-A", ((VarNode) aFoo).getType(), null);
        assertTrue("the injected object has no method", merged.getMethod() == null);
        pag.addEdge(merged, aFoo);
        pag.addEdge(merged, a1);
        pag.addEdge(merged, moreInFoo ? pFoo : a2);

        E6Reference.CsModel model = new E6Reference.CsModel(pta);
        Map<Node, Set<AllocNode>> bounded = E3UcfsPointsToTest.normalize(
                model.boundedPairs(E6IdrCsTest.DEPTH, E6IdrCsTest.MAX_STATES));
        Map<Node, Set<AllocNode>> ref = E6Reference.fieldsReference(pta);
        IdrGraph g = IdrExport.export(pta, IdrCalls.CS);
        IdrResult r = IdrSolve.solve(g, "parity");
        Map<Node, Set<AllocNode>> over = E6IdrCsTest.pts(g, r.getOver());
        Map<Node, Set<AllocNode>> under = E6IdrCsTest.pts(g, r.getUnder());
        List<Node[]> lost = E3UcfsPointsToTest.minus(bounded, over);
        System.out.println("E6CsMethodlessObjectTest Hyb2+merged->{a@foo, a1@main, " + (moreInFoo ? "p@foo" : "a2@main")
                + "}: bounded=" + E3UcfsPointsToTest.pairs(bounded) + " under=" + E3UcfsPointsToTest.pairs(under)
                + " over=" + E3UcfsPointsToTest.pairs(over) + " ref=" + E3UcfsPointsToTest.pairs(ref)
                + " lost=" + lost.size() + " truncated=" + model.truncated
                + " o2->v1 bounded=" + bounded.getOrDefault(v1, Set.of()).contains(objO2)
                + " over=" + over.getOrDefault(v1, Set.of()).contains(objO2)
                + " X(a@foo)=" + (g.idOf(new IdrVertex(E6Reference.ci(aFoo), Layer.F_IN)) >= 0)
                + " X(a1@main)=" + (g.idOf(new IdrVertex(E6Reference.ci(a1), Layer.F_IN)) >= 0)
                + " " + g.getCounters());
        for (Node[] l : lost) {
            System.out.println("E6CsMethodlessObjectTest lost: " + l[0] + " <- " + l[1]);
        }

        assertTrue("the injected object makes o2 -> v1 a pair of the CS language",
                bounded.getOrDefault(v1, Set.of()).contains(objO2));
        assertEquals("objects whose enumeration was cut", 0, model.truncated);
        assertTrue("(START o2-object, END v1) is in the over-approximation",
                over.getOrDefault(v1, Set.of()).contains(objO2));
        assertEquals("bounded CS pairs not in over" + (lost.isEmpty() ? "" : ", e.g. " + lost.get(0)[0] + " <- "
                + lost.get(0)[1]), 0, lost.size());
        assertTrue("under within over", E3UcfsPointsToTest.minus(under, over).isEmpty());
        assertTrue("over within the FIELDS reference", E3UcfsPointsToTest.minus(over, ref).isEmpty());
        assertEquals("cross-method new targets (objects with a method only)", 0,
                (int) g.getCounters().get("cross-method-new-targets"));
        assertTrue("counter methodless-new-targets", g.getCounters().containsKey("methodless-new-targets"));
    }

    private static boolean isLocal(Node n, String method, String name) {
        return E6Reference.ci(n) instanceof LocalVarNode lv && lv.getMethod().getName().equals(method)
                && lv.getVariable() instanceof Local l && l.getName().equals(name);
    }
}
