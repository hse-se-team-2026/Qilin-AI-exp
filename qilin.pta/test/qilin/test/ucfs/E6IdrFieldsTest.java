package qilin.test.ucfs;

import org.cfl_idr_with_gll.ApproximationKt;
import org.cfl_idr_with_gll.models.Path;
import org.junit.Test;
import org.ucfs.input.InputGraph;
import org.ucfs.input.TerminalInputLabel;
import org.ucfs.rsm.symbol.Term;
import qilin.core.PTA;
import qilin.core.PTAScene;
import qilin.core.pag.AllocNode;
import qilin.core.pag.Node;
import qilin.core.pag.VarNode;
import qilin.test.util.JunitTests;
import qilin.ucfs.LabeledEdge;
import qilin.ucfs.idr.IdrCalls;
import qilin.ucfs.idr.IdrExport;
import qilin.ucfs.idr.IdrGraph;
import qilin.ucfs.idr.IdrResult;
import qilin.ucfs.idr.IdrSolve;
import qilin.ucfs.idr.IdrVertex;
import qilin.ucfs.idr.Layer;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

/**
 * E6-S3 acceptance check (docs/ai/tickets/E6-S3.md): the FIELDS export of the PAG for cfl-idr
 * (IdrCalls.ERASED: call edges are `normal`, fields are brackets) and the in-process run of
 * cfl-idr-with-gll on it (IdrSolve). With one kind of bracket family the interleaved Dyck
 * language is a plain Dyck language, so cfl-idr's under- and over-approximation are both exact:
 * the points-to pairs must equal the Andersen fixpoint of the test (E6Reference.fieldsReference),
 * which is L_FT of Sridharan2005Demand / Melski2000Interconvertibility over the same CI PAG; and
 * Spark's own answer of the same run must be contained in it (the anchor of the export, r2).
 */
public class E6IdrFieldsTest extends JunitTests {

    static final Pattern LABEL = Pattern.compile("normal|(o|c)(p|b)--([0-9]+)(r?)");

    static List<kotlin.Pair<Integer, Integer>> list(Set<kotlin.Pair<Integer, Integer>> s) {
        return new ArrayList<>(s);
    }

    @Test
    public void fieldsExportEqualsAndersen() {
        List<String> bad = new ArrayList<>();
        int total = 0, extraOverRef2 = 0, programs = 0;
        for (String p : E6Reference.programs()) {
            PTAScene.junitReset();
            PTA pta = run(p, "insens");
            Map<Node, Set<AllocNode>> ref = E6Reference.fieldsReference(pta);
            Map<Node, Set<AllocNode>> ref2 = E3UcfsPointsToTest.normalize(E3UcfsPointsToTest.andersen(
                    E3ReceiverAssignTest.expectedEdges(pta), E3UcfsPointsToTest.Filters.NONE, true));
            IdrGraph g = IdrExport.export(pta, IdrCalls.ERASED);
            IdrResult r = IdrSolve.solve(g, "parity");
            Map<Node, Set<AllocNode>> under = E3UcfsPointsToTest.normalize(IdrExport.pointsTo(g, list(r.getUnder())));
            Map<Node, Set<AllocNode>> over = E3UcfsPointsToTest.normalize(IdrExport.pointsTo(g, list(r.getOver())));
            if (!under.equals(ref)) {
                bad.add(p + ": under != reference " + E3UcfsPointsToTest.diff(under, ref));
            }
            if (!over.equals(ref)) {
                bad.add(p + ": over != reference " + E3UcfsPointsToTest.diff(over, ref));
            }
            if (!E3UcfsPointsToTest.minus(ref2, ref).isEmpty()) {
                bad.add(p + ": reference misses pairs of E3 REF2: " + E3UcfsPointsToTest.minus(ref2, ref).size());
            }
            total += E3UcfsPointsToTest.pairs(ref);
            extraOverRef2 += E3UcfsPointsToTest.minus(ref, ref2).size();
            programs++;
            System.out.println("E6IdrFieldsTest " + p + " pairs=" + E3UcfsPointsToTest.pairs(over) + " ref="
                    + E3UcfsPointsToTest.pairs(ref) + " ref2=" + E3UcfsPointsToTest.pairs(ref2) + " " + g.getCounters());
        }
        System.out.println("E6IdrFieldsTest total: programs=" + programs + " pairs=" + total
                + " exceptionRebuildExtra=" + extraOverRef2);
        assertEquals(61, programs);
        assertTrue(String.join("\n", bad), bad.isEmpty());
    }

    /**
     * Anchor of the export in Spark (r2, critic MAJOR-2; as E3-S4 Spark within UCFS): with insens the
     * export uses the call graph of the same Spark run, binds receivers along it (a superset of the
     * objects Spark dispatches to this), sends exceptions to their handlers without the catch type (a
     * superset of the objects Spark dispatched) and has no type filter, so every pair of Spark's CI
     * points-to sets is in cfl-idr's answer on the FIELDS export. Catches lost paths of the export that
     * the test's own reference would share (both read the same PAG).
     */
    @Test
    public void sparkWithinFieldsExport() {
        List<String> bad = new ArrayList<>();
        int programs = 0, sparkPairs = 0, overPairs = 0;
        for (String p : E6Reference.programs()) {
            PTAScene.junitReset();
            PTA pta = run(p, "insens");
            IdrGraph g = IdrExport.export(pta, IdrCalls.ERASED);
            IdrResult r = IdrSolve.solve(g, "parity");
            Map<Node, Set<AllocNode>> over = E3UcfsPointsToTest.normalize(IdrExport.pointsTo(g, list(r.getOver())));
            Map<Node, Set<AllocNode>> spark = E3UcfsPointsToTest.normalize(
                    E3UcfsPointsToTest.spark(pta, E3UcfsPointsToTest.ciVars(pta.getPag())));
            List<Node[]> missing = E3UcfsPointsToTest.minus(spark, over);
            if (!missing.isEmpty()) {
                bad.add(p + ": Spark pairs not in the FIELDS answer: " + missing.size() + ", e.g. "
                        + missing.get(0)[0] + " <- " + missing.get(0)[1]);
            }
            programs++;
            sparkPairs += E3UcfsPointsToTest.pairs(spark);
            overPairs += E3UcfsPointsToTest.pairs(over);
        }
        System.out.println("E6IdrFieldsTest spark: programs=" + programs + " spark=" + sparkPairs + " over=" + overPairs);
        assertEquals(61, programs);
        assertTrue("Spark has points-to pairs: " + sparkPairs, sparkPairs > 0);
        assertTrue(String.join("\n", bad), bad.isEmpty());
    }

    /** IdrSolve returns what cfl-idr-with-gll answers on the same graph, built here from the edge list. */
    @Test
    public void solveIsCflIdrOnTheExportedGraph() {
        for (String p : List.of(E6Reference.CORE + "field.InstanceLoad", E6Reference.CORE + "natives.RefArrayGet",
                E6Reference.CONTEXT + "cfa.CFA1k1")) {
            PTAScene.junitReset();
            PTA pta = run(p, "insens");
            IdrGraph g = IdrExport.export(pta, IdrCalls.ERASED);
            IdrResult r = IdrSolve.solve(g, "parity");
            Set<Path<Integer>> under = ApproximationKt.getUnderApprox(graph(g), false,
                    org.cfl_idr_with_gll.terminal.DefaultTerminalFormat.INSTANCE);
            Set<Path<Integer>> over = ApproximationKt.getMROverApprox(graph(g), "parity", 1, under, false,
                    org.cfl_idr_with_gll.terminal.DefaultTerminalFormat.INSTANCE);
            assertEquals(p + " under", asPairs(under), r.getUnder());
            assertEquals(p + " over", asPairs(over), r.getOver());
        }
    }

    static InputGraph<Integer, TerminalInputLabel> graph(IdrGraph g) {
        InputGraph<Integer, TerminalInputLabel> ig = new InputGraph<>();
        for (LabeledEdge e : g.getEdges()) {
            ig.addVertex(e.getFrom());
            ig.addVertex(e.getTo());
            ig.addEdge(e.getFrom(), new TerminalInputLabel(new Term<>(e.getLabel())), e.getTo());
        }
        return ig;
    }

    static Set<kotlin.Pair<Integer, Integer>> asPairs(Set<Path<Integer>> ps) {
        Set<kotlin.Pair<Integer, Integer>> out = new HashSet<>();
        for (Path<Integer> x : ps) {
            out.add(new kotlin.Pair<>(x.getSource(), x.getTarget()));
        }
        return out;
    }

    /**
     * Shape of the FIELDS graph (E6.md D4, D5): labels `normal`, `ob--i`/`cb--i` (store/load of field
     * i) and `ob--ir`/`cb--ir` (load-bar/store-bar), no parentheses, no gadget vertices; every edge
     * goes between the layers its label allows: normal OBJ->F, F->F, B->B, B->OBJ; ob--i F->B;
     * cb--i F->F; ob--ir B->B; cb--ir F->B; field indices are 0..#fields-1; objects are the
     * source vertices (OBJ) and variables the answer vertices (F).
     */
    @Test
    public void fieldsGraphShape() {
        List<String> bad = new ArrayList<>();
        for (String p : E6Reference.programs()) {
            PTAScene.junitReset();
            PTA pta = run(p, "insens");
            IdrGraph g = IdrExport.export(pta, IdrCalls.ERASED);
            Set<Integer> fieldIds = new HashSet<>();
            for (LabeledEdge e : g.getEdges()) {
                Layer a = g.getVertices().get(e.getFrom()).getLayer();
                Layer b = g.getVertices().get(e.getTo()).getLayer();
                Matcher m = LABEL.matcher(e.getLabel());
                String kind;
                if (!m.matches() || "p".equals(m.group(2))) {
                    bad.add(p + ": label " + e.getLabel());
                    continue;
                } else if (e.getLabel().equals("normal")) {
                    kind = "normal";
                } else {
                    kind = m.group(1) + "b" + m.group(4);
                    int f = Integer.parseInt(m.group(3));
                    fieldIds.add(f);
                    if (f >= g.getFields().size()) {
                        bad.add(p + ": field index " + f + " >= " + g.getFields().size());
                    }
                }
                boolean ok = switch (kind) {
                    case "normal" -> (a == Layer.OBJ && b == Layer.F) || (a == Layer.F && b == Layer.F)
                            || (a == Layer.B && b == Layer.B) || (a == Layer.B && b == Layer.OBJ);
                    case "ob" -> a == Layer.F && b == Layer.B;
                    case "cb" -> a == Layer.F && b == Layer.F;
                    case "obr" -> a == Layer.B && b == Layer.B;
                    case "cbr" -> a == Layer.F && b == Layer.B;
                    default -> false;
                };
                if (!ok) {
                    bad.add(p + ": " + e.getLabel() + " from " + a + " to " + b);
                }
            }
            if (fieldIds.size() != g.getFields().size()) {
                bad.add(p + ": " + fieldIds.size() + " field ids used, fields=" + g.getFields().size());
            }
            for (int i = 0; i < g.getVertices().size(); i++) {
                IdrVertex v = g.getVertices().get(i);
                if (v.getLayer() != Layer.OBJ && v.getLayer() != Layer.F && v.getLayer() != Layer.B) {
                    bad.add(p + ": vertex " + v);
                }
                if (v.getNode() instanceof AllocNode o && v.getLayer() == Layer.OBJ && g.sourceVertex(o) != i) {
                    bad.add(p + ": sourceVertex of " + o);
                }
                if (v.getNode() instanceof VarNode x && v.getLayer() == Layer.F && g.answerVertex(x) != i) {
                    bad.add(p + ": answerVertex of " + x);
                }
            }
        }
        assertTrue(String.join("\n", bad.subList(0, Math.min(20, bad.size()))), bad.isEmpty());
    }
}
