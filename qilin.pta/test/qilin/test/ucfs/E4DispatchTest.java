package qilin.test.ucfs;

import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.Test;
import qilin.core.PTAScene;
import qilin.core.pag.AllocNode;
import qilin.core.pag.VarNode;
import qilin.core.pag.VirtualCallSite;
import qilin.pta.tools.UcfsPTA;
import qilin.pta.ucfs.UcfsCompare;
import qilin.test.util.JunitTests;
import qilin.ucfs.ReceiverBinding;
import qilin.util.PTAUtils;
import soot.Scene;
import soot.SootMethod;
import soot.Unit;
import soot.jimple.SpecialInvokeExpr;
import soot.jimple.toolkits.callgraph.Edge;
import soot.util.queue.QueueReader;

/**
 * E4-S4 acceptance check (docs/ai/tickets/E4-S4.md): UcfsCompare.dispatch, one step of dispatch over
 * the objects of a view at every instance call site the solver recorded.
 *
 * <p>On the 43 small programs of E3, both receiver bindings, all three views:
 * <ol>
 *   <li>the edges returned = the (site, target) pairs that the test finds by Qilin's dispatch
 *       (PTAUtils.dispatch over the CI objects of the receiver variable in the view, with the
 *       canStoreType check of CallGraphBuilder.dispatch for special invokes) and that Spark's CI call
 *       graph does not have at that site; counts[0] = all pairs found, counts[1] = Spark's CI call
 *       edges out of the recorded sites;</li>
 *   <li>in the view SPARK the dispatch reproduces Spark's call graph at these sites: no new edge and
 *       the pairs found = Spark's edges there (the solver builds these edges by the same dispatch);</li>
 *   <li>the new edges of UCFS_TYPED are new edges of UCFS too (UCFS_TYPED is a subset of UCFS).</li>
 * </ol>
 */
public class E4DispatchTest extends JunitTests {

    private static final String P = E3UcfsPointsToTest.P;

    /** {found, new, cgAtSites} computed here, as sets of List.of(unit, target). */
    static List<Set<List<Object>>> reference(UcfsPTA pta, UcfsPTA.View view) {
        Map<Unit, Set<SootMethod>> cg = new HashMap<>();
        for (Edge e : pta.getCallGraph()) {
            if (e.srcUnit() != null) {
                cg.computeIfAbsent(e.srcUnit(), k -> new HashSet<>()).add(e.tgt());
            }
        }
        Set<List<Object>> found = new HashSet<>();
        Set<List<Object>> fresh = new HashSet<>();
        Set<List<Object>> atSites = new HashSet<>();
        for (Map.Entry<VarNode, Collection<VirtualCallSite>> en : pta.getCgb().getReceiverToSitesMap().entrySet()) {
            Set<AllocNode> objs = pta.pointsTo(en.getKey().base(), view);
            for (VirtualCallSite site : en.getValue()) {
                for (SootMethod t : cg.getOrDefault(site.getUnit(), Set.of())) {
                    atSites.add(List.of(site.getUnit(), t));
                }
                for (AllocNode o : objs) {
                    QueueReader<SootMethod> ts = PTAUtils.dispatch(o.getType(), site);
                    while (ts.hasNext()) {
                        SootMethod t = ts.next();
                        if (site.iie() instanceof SpecialInvokeExpr
                                && !Scene.v().getFastHierarchy().canStoreType(o.getType(), t.getDeclaringClass().getType())) {
                            continue;
                        }
                        found.add(List.of(site.getUnit(), t));
                        if (!cg.getOrDefault(site.getUnit(), Set.of()).contains(t)) {
                            fresh.add(List.of(site.getUnit(), t));
                        }
                    }
                }
            }
        }
        return List.of(found, fresh, atSites);
    }

    @Test
    public void dispatchAgainstSparkCallGraph() {
        List<String> failures = new ArrayList<>();
        long[] total = new long[4];
        for (ReceiverBinding b : ReceiverBinding.values()) {
            for (String p : E3UcfsPointsToTest.PROGRAMS) {
                PTAScene.junitReset();
                UcfsPTA pta = E4UcfsPtaTest.runUcfs(P + p, b);
                Map<UcfsPTA.View, Set<List<Object>>> fresh = new HashMap<>();
                for (UcfsPTA.View view : UcfsPTA.View.values()) {
                    String tag = p + " [" + b + ", " + view + "]";
                    int[] counts = new int[2];
                    List<UcfsCompare.NewEdge> es = UcfsCompare.dispatch(pta, view, counts);
                    Set<List<Object>> got = new HashSet<>();
                    for (UcfsCompare.NewEdge e : es) {
                        got.add(List.of(e.site(), e.target()));
                        if (e.view() != view) {
                            failures.add(tag + ": edge of view " + e.view());
                        }
                    }
                    List<Set<List<Object>>> ref = reference(pta, view);
                    if (got.size() != es.size() || !got.equals(ref.get(1))) {
                        failures.add(tag + ": new edges " + es.size() + " " + es.stream().limit(2).toList()
                                + ", reference " + ref.get(1).size());
                    }
                    if (counts[0] != ref.get(0).size() || counts[1] != ref.get(2).size()) {
                        failures.add(tag + ": counts " + counts[0] + "/" + counts[1] + ", reference "
                                + ref.get(0).size() + "/" + ref.get(2).size());
                    }
                    if (view == UcfsPTA.View.SPARK && (!ref.get(1).isEmpty() || !ref.get(0).equals(ref.get(2)))) {
                        failures.add(tag + ": dispatch over Spark's sets does not reproduce Spark's call graph");
                    }
                    fresh.put(view, got);
                    if (view == UcfsPTA.View.UCFS) {
                        total[0] += ref.get(2).size();
                        total[1] += ref.get(0).size();
                        total[2] += got.size();
                    }
                }
                if (!fresh.get(UcfsPTA.View.UCFS).containsAll(fresh.get(UcfsPTA.View.UCFS_TYPED))) {
                    failures.add(p + " [" + b + "]: a new edge of UCFS_TYPED is not a new edge of UCFS");
                }
                total[3] += fresh.get(UcfsPTA.View.UCFS_TYPED).size();
            }
        }
        System.out.println("E4DispatchTest total: cgEdgesAtSites=" + total[0] + " foundUcfs=" + total[1]
                + " newUcfs=" + total[2] + " newTyped=" + total[3]);
        assertTrue(String.join("\n", failures), failures.isEmpty());
    }
}
