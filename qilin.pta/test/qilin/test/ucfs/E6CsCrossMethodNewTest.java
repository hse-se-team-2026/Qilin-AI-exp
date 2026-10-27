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
import soot.Local;
import soot.SootMethod;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

/**
 * E6-S4, the object end of the erasure loop rule (ticket E6-S4, "Дополнение лида (2026-10-27)", O4a;
 * E6.md D6; a variant of probe P5 of critic-E6, MAJOR-1). Not an acceptance test of the plan: the
 * implementer's own check that the loops of a context-insensitive variable X also come from the method
 * of the object of a cross-method {@code new} into X, when no other edge of X touches that method.
 *
 * <p>Program qilin.microben.context.hyb.Hyb2: {@code main} calls {@code a1 = b1.foo(o1)},
 * {@code a2 = b2.foo(o2)} and loads {@code v1 = a1.f}; {@code foo(p)} calls {@code a = create()} (site
 * s0) and stores {@code a.f = p}; the static {@code create()} allocates the object A. After the run the
 * test adds to the PAG the edge A -> a1 the way the kernel adds the Finalizer.register edges
 * ({@code PAG.addEdge(object, variable)}, Solver.handleImplicitCallToFinalizerRegister): a1 (in main)
 * becomes context-insensitive, and its other edges (the return of foo into a1, the load a1.f) touch
 * main and foo only, never create().
 *
 * <p>The pair o2 -> v1 is in the CS language only through the new edge (without it notAlias(v1, v2)
 * of the program holds): o2 enters foo at the site of b2.foo (push c2), is stored into a.f, goes
 * backwards out of the return of create at s0 (push s0) to the object A, jumps to a1 (the stack is
 * erased) and is loaded into v1. In the graph, the parentheses c2 and s0 open on that path must close
 * at F_IN(a1): the loops there need s0, whose callee create() reaches neither main nor foo; only the
 * object end of the edge A -> a1 (the method create() of A) gives it. Loops by the method of a1 alone
 * (the rule of round 1) miss c2 and s0; loops by the ends of the edges of a1 without the object end
 * miss s0. The test requires (START of the object of o2, END v1) in the over-approximation, every bounded
 * pair of the CS language (E6Reference.CsModel) in it, and it within the FIELDS reference.
 */
public class E6CsCrossMethodNewTest extends JunitTests {

    @Test
    public void erasureLoopsTakeTheObjectEnd() {
        PTAScene.junitReset();
        PTA pta = run(E6Reference.CONTEXT + "hyb.Hyb2", "insens");
        PAG pag = pta.getPag();
        AllocNode objA = null;
        for (AllocNode o : pag.getAlloc().keySet()) {
            SootMethod m = o.base().getMethod();
            if (m != null && m.getName().equals("create")) {
                assertTrue("one object in create(): " + objA + ", " + o, objA == null);
                objA = o;
            }
        }
        Node a1 = null;
        Node v1 = null;
        for (Map.Entry<FieldRefNode, Set<VarNode>> e : pag.getLoad().entrySet()) {
            if (isLocal(e.getKey().getBase(), "main", "a1")) {
                a1 = e.getKey().getBase();
                for (VarNode z : e.getValue()) {
                    if (isLocal(z, "main", "v1")) {
                        v1 = E6Reference.ci(z);
                    }
                }
            }
        }
        Node o2 = null;
        for (E6Reference.CallEdge c : E6Reference.callEdges(pta)) {
            if (c.entry() && isLocal(c.from(), "main", "o2")) {
                o2 = c.from();
            }
        }
        assertTrue("Hyb2 has the object of create(), a1 with v1 = a1.f and o2 in main: " + objA + ", " + a1
                + ", " + v1 + ", " + o2, objA != null && a1 != null && v1 != null && o2 != null);
        Map<Node, Set<AllocNode>> refBefore = E6Reference.fieldsReference(pta);
        assertEquals("o2 points to one object", 1, refBefore.get(o2).size());
        AllocNode objO2 = refBefore.get(o2).iterator().next();
        Map<Node, Set<AllocNode>> before = E3UcfsPointsToTest.normalize(
                new E6Reference.CsModel(pta).boundedPairs(E6IdrCsTest.DEPTH, E6IdrCsTest.MAX_STATES));
        assertFalse("without the injected edge the CS language has no o2 -> v1",
                before.getOrDefault(v1, Set.of()).contains(objO2));

        // the premise: no edge of a1 but the injected one has an end in create()
        Node a1ci = E6Reference.ci(a1);
        List<String> touching = new ArrayList<>();
        for (E6Reference.CallEdge c : E6Reference.callEdges(pta)) {
            if (c.from().equals(a1ci) || c.to().equals(a1ci)) {
                for (Node n : List.of(c.from(), c.to())) {
                    if (n instanceof LocalVarNode lv && lv.getMethod().getName().equals("create")) {
                        touching.add(c.from() + " -> " + c.to());
                    }
                }
            }
        }
        assertTrue("edges of a1 into create(): " + touching, touching.isEmpty());

        pag.addEdge(objA, a1);

        E6Reference.CsModel model = new E6Reference.CsModel(pta);
        Map<Node, Set<AllocNode>> bounded = E3UcfsPointsToTest.normalize(
                model.boundedPairs(E6IdrCsTest.DEPTH, E6IdrCsTest.MAX_STATES));
        Map<Node, Set<AllocNode>> ref = E6Reference.fieldsReference(pta);
        IdrGraph g = IdrExport.export(pta, IdrCalls.CS);
        IdrResult r = IdrSolve.solve(g, "parity");
        Map<Node, Set<AllocNode>> over = E6IdrCsTest.pts(g, r.getOver());
        Map<Node, Set<AllocNode>> under = E6IdrCsTest.pts(g, r.getUnder());
        List<Node[]> lost = E3UcfsPointsToTest.minus(bounded, over);
        System.out.println("E6CsCrossMethodNewTest Hyb2+A->a1: bounded=" + E3UcfsPointsToTest.pairs(bounded)
                + " under=" + E3UcfsPointsToTest.pairs(under) + " over=" + E3UcfsPointsToTest.pairs(over)
                + " lost=" + lost.size() + " truncated=" + model.truncated
                + " o2->v1 bounded=" + bounded.getOrDefault(v1, Set.of()).contains(objO2)
                + " over=" + over.getOrDefault(v1, Set.of()).contains(objO2) + " " + g.getCounters());

        assertTrue("the injected edge makes o2 -> v1 a pair of the CS language",
                bounded.getOrDefault(v1, Set.of()).contains(objO2));
        assertEquals("cross-method new targets", 1, (int) g.getCounters().get("cross-method-new-targets"));
        assertTrue("(START o2-object, END v1) is in the over-approximation",
                over.getOrDefault(v1, Set.of()).contains(objO2));
        assertEquals("bounded CS pairs not in over" + (lost.isEmpty() ? "" : ", e.g. " + lost.get(0)[0] + " <- "
                + lost.get(0)[1]), 0, lost.size());
        assertTrue("under within over", E3UcfsPointsToTest.minus(under, over).isEmpty());
        assertTrue("over within the FIELDS reference", E3UcfsPointsToTest.minus(over, ref).isEmpty());
    }

    private static boolean isLocal(Node n, String method, String name) {
        return E6Reference.ci(n) instanceof LocalVarNode lv && lv.getMethod().getName().equals(method)
                && lv.getVariable() instanceof Local l && l.getName().equals(name);
    }
}
