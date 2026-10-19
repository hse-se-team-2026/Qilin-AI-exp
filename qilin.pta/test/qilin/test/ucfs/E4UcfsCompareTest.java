package qilin.test.ucfs;

import static org.junit.Assert.assertTrue;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.Test;
import qilin.core.PTAScene;
import qilin.core.pag.AllocNode;
import qilin.core.pag.Node;
import qilin.pta.tools.UcfsPTA;
import qilin.pta.ucfs.UcfsCompare;
import qilin.test.util.JunitTests;
import qilin.ucfs.ReceiverBinding;

/**
 * E4-S3 acceptance check (docs/ai/tickets/E4-S3.md): qilin.pta.ucfs.UcfsCompare, the same-run
 * comparison of the views of UcfsPTA.
 *
 * <p>On the 43 small programs of E3 and both receiver bindings:
 * <ol>
 *   <li>UcfsCompare.pairs(pta) has one row per pair (CI variable, CI object) of SPARK or UCFS (with
 *       ROOT), with the flags inSpark / inUcfs / inTyped and the class computed here by the
 *       references of E3 (E3.md D16): SAME, MISSING, or the first step that removes the pair:
 *       R3 (CALL_GRAPH only: Andersen without filters on the ANALYSIS input), R4b (ROOT invisible),
 *       R1 (+ declared types of variables and field nodes), R2 (+ cast types), R5 (+ no store/load on
 *       empty arrays), UNEXPLAINED if the last step keeps it;</li>
 *   <li>UcfsCompare.metrics(pta) holds, per metric line and view, the value printed by Qilin's
 *       SimplifiedEvaluator on pta in that view, and leaves the view of pta as it was;</li>
 *   <li>UcfsCompare.counters(pta, pairs(pta)) (E4.md, lead decision B2 and M2): the "new" edges of the
 *       solved graph and among them the edges the solver made from Spark's points-to (receiver into
 *       this, exception, Finalizer.register) = the E3 classification of the "new" edges
 *       (E3UcfsPointsToTest.newKinds, which looks at the allocation statements first; class OTHER is
 *       empty); the SAME pairs that survive in the Andersen reference of the binding's input without
 *       the "this" seeds and without all seeds; the pairs of the last reference step = the pairs of
 *       REF_T (all filters of the solver) = the pairs of SPARK.</li>
 * </ol>
 */
public class E4UcfsCompareTest extends JunitTests {

    private static final String P = E3UcfsPointsToTest.P;

    static boolean has(Map<Node, Set<AllocNode>> m, Node v, AllocNode o) {
        return m.getOrDefault(v, Set.of()).contains(o);
    }

    /** The rows expected for pta: "var|obj|S|U|T|class" with the CI nodes' identity strings. */
    static Set<List<Object>> expectedRows(UcfsPTA pta, ReceiverBinding b) {
        E3UcfsPointsToTest.Edges ga = new E3UcfsPointsToTest.Edges(pta.getPag());
        E3UcfsPointsToTest.Edges gb = b == ReceiverBinding.ANALYSIS ? ga : E3ReceiverAssignTest.expectedEdges(pta);
        Set<AllocNode> zero = E3UcfsPointsToTest.zeroNumbered(pta.getPag());
        AllocNode root = pta.getRootNode().base();
        Map<Node, Set<AllocNode>> ref = E3UcfsPointsToTest.andersen(gb, E3UcfsPointsToTest.Filters.NONE, true);
        Map<Node, Set<AllocNode>> refT = E3UcfsPointsToTest.andersen(ga, new E3UcfsPointsToTest.Filters(zero, true, true, true), true);
        Map<Node, Set<AllocNode>> typed = E4UcfsPtaTest.typed(E4UcfsPtaTest.withoutRoot(ref, root));
        List<String> names = new ArrayList<>();
        List<Map<Node, Set<AllocNode>>> steps = new ArrayList<>();
        if (b == ReceiverBinding.CALL_GRAPH) {
            names.add("R3");
            steps.add(E3UcfsPointsToTest.andersen(ga, E3UcfsPointsToTest.Filters.NONE, true));
        }
        names.add("R4b");
        steps.add(E3UcfsPointsToTest.andersen(ga, new E3UcfsPointsToTest.Filters(zero, false, false, false), true));
        names.add("R1");
        steps.add(E3UcfsPointsToTest.andersen(ga, new E3UcfsPointsToTest.Filters(zero, false, true, false), true));
        names.add("R2");
        steps.add(E3UcfsPointsToTest.andersen(ga, new E3UcfsPointsToTest.Filters(zero, true, true, false), true));
        names.add("R5");
        steps.add(refT);
        Set<List<Object>> rows = new HashSet<>();
        for (Node v : E3UcfsPointsToTest.ciVars(pta.getPag())) {
            Set<AllocNode> all = new HashSet<>(refT.getOrDefault(v, Set.of()));
            all.addAll(ref.getOrDefault(v, Set.of()));
            for (AllocNode o : all) {
                boolean s = has(refT, v, o);
                boolean u = has(ref, v, o);
                String cls;
                if (s && u) {
                    cls = "SAME";
                } else if (s) {
                    cls = "MISSING";
                } else {
                    cls = "UNEXPLAINED";
                    for (int i = 0; i < steps.size(); i++) {
                        if (!has(steps.get(i), v, o)) {
                            cls = names.get(i);
                            break;
                        }
                    }
                }
                rows.add(List.of(v, o, s, u, has(typed, v, o), cls));
            }
        }
        return rows;
    }

    @Test
    public void pairsAndClassesAgainstReferences() {
        List<String> failures = new ArrayList<>();
        Map<String, Integer> total = new java.util.TreeMap<>();
        for (ReceiverBinding b : ReceiverBinding.values()) {
            for (String p : E3UcfsPointsToTest.PROGRAMS) {
                PTAScene.junitReset();
                UcfsPTA pta = E4UcfsPtaTest.runUcfs(P + p, b);
                List<UcfsCompare.PairRow> rows = UcfsCompare.pairs(pta);
                Set<List<Object>> got = new HashSet<>();
                Set<List<Object>> keys = new HashSet<>();
                for (UcfsCompare.PairRow r : rows) {
                    got.add(List.of(r.var(), r.obj(), r.inSpark(), r.inUcfs(), r.inTyped(), r.cls()));
                    keys.add(List.of(r.var(), r.obj()));
                }
                String tag = p + " [" + b + "]";
                if (keys.size() != rows.size()) {
                    failures.add(tag + ": " + (rows.size() - keys.size()) + " repeated pairs in UcfsCompare.pairs");
                }
                Set<List<Object>> exp = expectedRows(pta, b);
                if (!got.equals(exp)) {
                    Set<List<Object>> a = new HashSet<>(got);
                    a.removeAll(exp);
                    Set<List<Object>> c = new HashSet<>(exp);
                    c.removeAll(got);
                    failures.add(tag + ": rows differ, unexpected " + a.size() + " " + a.stream().limit(3).toList()
                            + ", missing " + c.size() + " " + c.stream().limit(3).toList());
                }
                StringBuilder line = new StringBuilder("E4UcfsCompareTest " + tag + ":");
                Map<String, Integer> cnt = new java.util.TreeMap<>();
                for (List<Object> r : exp) {
                    cnt.merge((String) r.get(5), 1, Integer::sum);
                }
                cnt.forEach((k, n) -> {
                    line.append(' ').append(k).append('=').append(n);
                    total.merge(b + "/" + k, n, Integer::sum);
                });
                System.out.println(line);
            }
        }
        System.out.println("E4UcfsCompareTest total: " + total);
        assertTrue(String.join("\n", failures), failures.isEmpty());
    }

    @Test
    public void countersAgainstReferences() {
        List<String> failures = new ArrayList<>();
        long[] total = new long[7];
        for (ReceiverBinding b : ReceiverBinding.values()) {
            for (String p : E3UcfsPointsToTest.PROGRAMS) {
                PTAScene.junitReset();
                UcfsPTA pta = E4UcfsPtaTest.runUcfs(P + p, b);
                String tag = p + " [" + b + "]";
                Map<String, Integer> got = UcfsCompare.counters(pta, UcfsCompare.pairs(pta));
                if (!new ArrayList<>(got.keySet()).equals(UcfsCompare.COUNTERS)) {
                    failures.add(tag + ": counter names " + got.keySet());
                    continue;
                }
                Map<E3UcfsPointsToTest.NewKind, Integer> kinds = E3UcfsPointsToTest.newKinds(pta, pta.getUcfsGraph(), null);
                int news = kinds.values().stream().mapToInt(Integer::intValue).sum();
                if (kinds.get(E3UcfsPointsToTest.NewKind.OTHER) != 0) {
                    failures.add(tag + ": E3 class OTHER of new edges is " + kinds.get(E3UcfsPointsToTest.NewKind.OTHER));
                }
                E3UcfsPointsToTest.Edges ga = new E3UcfsPointsToTest.Edges(pta.getPag());
                E3UcfsPointsToTest.Edges gb = b == ReceiverBinding.ANALYSIS ? ga : E3ReceiverAssignTest.expectedEdges(pta);
                Set<List<Object>> stmts = E3UcfsPointsToTest.statementAllocs(pta);
                AllocNode root = pta.getRootNode().base();
                Map<Node, Set<AllocNode>> noThis = E3UcfsPointsToTest.andersen(gb.with((o, v) ->
                        E3UcfsPointsToTest.classify(stmts, root, o, v) == E3UcfsPointsToTest.NewKind.RECEIVER, List.of()),
                        E3UcfsPointsToTest.Filters.NONE, true);
                Map<Node, Set<AllocNode>> noSeeds = E3UcfsPointsToTest.andersen(gb.with((o, v) -> {
                    E3UcfsPointsToTest.NewKind k = E3UcfsPointsToTest.classify(stmts, root, o, v);
                    return k != E3UcfsPointsToTest.NewKind.STATEMENT && k != E3UcfsPointsToTest.NewKind.ROOT;
                }, List.of()), E3UcfsPointsToTest.Filters.NONE, true);
                Map<Node, Set<AllocNode>> refT = E3UcfsPointsToTest.andersen(ga,
                        new E3UcfsPointsToTest.Filters(E3UcfsPointsToTest.zeroNumbered(pta.getPag()), true, true, true), true);
                int keptThis = 0;
                int keptAll = 0;
                for (List<Object> r : expectedRows(pta, b)) {
                    if (r.get(5).equals("SAME")) {
                        keptThis += has(noThis, (Node) r.get(0), (AllocNode) r.get(1)) ? 1 : 0;
                        keptAll += has(noSeeds, (Node) r.get(0), (AllocNode) r.get(1)) ? 1 : 0;
                    }
                }
                int last = refT.values().stream().mapToInt(Set::size).sum();
                int spark = 0;
                for (Node v : E3UcfsPointsToTest.ciVars(pta.getPag())) {
                    spark += pta.pointsTo((qilin.core.pag.VarNode) v, UcfsPTA.View.SPARK).size();
                }
                int[] exp = {news, kinds.get(E3UcfsPointsToTest.NewKind.RECEIVER), kinds.get(E3UcfsPointsToTest.NewKind.EXCEPTION),
                        kinds.get(E3UcfsPointsToTest.NewKind.FINALIZER), keptThis, keptAll, last};
                for (int i = 0; i < exp.length; i++) {
                    String k = UcfsCompare.COUNTERS.get(i);
                    if (got.get(k) != exp[i]) {
                        failures.add(tag + ": " + k + " " + got.get(k) + ", reference " + exp[i]);
                    }
                    total[i] += exp[i];
                }
                if (last != spark) {
                    failures.add(tag + ": pairs of REF_T " + last + " != pairs of SPARK " + spark);
                }
                if (b == ReceiverBinding.CALL_GRAPH && got.get("seed-this-edges") != 0) {
                    failures.add(tag + ": CALL_GRAPH export has seed edges into this");
                }
            }
        }
        StringBuilder line = new StringBuilder("E4UcfsCompareTest counters total:");
        for (int i = 0; i < total.length; i++) {
            line.append(' ').append(UcfsCompare.COUNTERS.get(i)).append('=').append(total[i]);
        }
        System.out.println(line);
        assertTrue(String.join("\n", failures), failures.isEmpty());
    }

    @Test
    public void metricsPerViewAsQilinPrintsThem() {
        List<String> failures = new ArrayList<>();
        UcfsPTA.View[] order = {UcfsPTA.View.SPARK, UcfsPTA.View.UCFS, UcfsPTA.View.UCFS_TYPED};
        for (ReceiverBinding b : ReceiverBinding.values()) {
            for (String p : E3UcfsPointsToTest.PROGRAMS) {
                PTAScene.junitReset();
                UcfsPTA pta = E4UcfsPtaTest.runUcfs(P + p, b);
                String tag = p + " [" + b + "]";
                Map<String, String[]> m = null;
                for (UcfsPTA.View start : UcfsPTA.View.values()) {
                    pta.setView(start);
                    m = UcfsCompare.metrics(pta);
                    if (pta.getView() != start) {
                        failures.add(tag + ": metrics() called in view " + start + " left the view " + pta.getView());
                    }
                }
                if (!new ArrayList<>(m.keySet()).equals(UcfsCompare.METRICS)) {
                    failures.add(tag + ": metric lines " + m.keySet());
                    continue;
                }
                for (int i = 0; i < order.length; i++) {
                    pta.setView(order[i]);
                    Map<String, String> ev = E4UcfsPtaTest.evaluate(pta);
                    for (String k : UcfsCompare.METRICS) {
                        if (!ev.get(k).equals(m.get(k)[i])) {
                            failures.add(tag + " " + order[i] + " " + k + ": metrics()=" + m.get(k)[i] + ", evaluator=" + ev.get(k));
                        }
                    }
                }
            }
        }
        assertTrue(String.join("\n", failures), failures.isEmpty());
    }
}
