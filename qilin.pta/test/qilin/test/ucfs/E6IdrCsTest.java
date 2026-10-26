package qilin.test.ucfs;

import org.junit.Test;
import qilin.core.PTA;
import qilin.core.PTAScene;
import qilin.core.pag.AllocNode;
import qilin.core.pag.GlobalVarNode;
import qilin.core.pag.LocalVarNode;
import qilin.core.pag.Node;
import qilin.core.pag.Parm;
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
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

/**
 * E6-S4 acceptance check (docs/ai/tickets/E6-S4.md): the context-sensitive export (IdrCalls.CS:
 * call-site parentheses, partial balance by START/END gadgets, context erasure at the
 * context-insensitive variables) and the diagnostic export with cfl-idr's own fully balanced
 * semantics (IdrCalls.BALANCED), on the 61 programs of E6Reference.
 *
 * Oracles, none of them computed by the code under test (E6.md D7):
 * <ul>
 *   <li>soundness: every pair of the bounded CS language (E6Reference.CsModel, stacks <= 3) is in
 *       cfl-idr's over-approximation; every mayAlias assertion of the sources holds in it;</li>
 *   <li>chain: under <= over <= FIELDS reference (dropping the call labels only adds paths);</li>
 *   <li>precision: every notAlias assertion of the context-sensitivity programs
 *       (qilin.microben.context, written by the Qilin authors for k-CFA/k-obj) holds in the
 *       over-approximation; the CI reference violates at least one of them (so CS matters);</li>
 *   <li>the fully balanced export misses pairs and assertions that the CS export keeps.</li>
 * </ul>
 */
public class E6IdrCsTest extends JunitTests {

    static final int DEPTH = 3;
    static final int MAX_STATES = 2_000_000;

    static Map<Node, Set<AllocNode>> pts(IdrGraph g, Set<kotlin.Pair<Integer, Integer>> pairs) {
        return E3UcfsPointsToTest.normalize(IdrExport.pointsTo(g, new ArrayList<>(pairs)));
    }

    @Test
    public void csSoundBoundedAndPrecise() {
        List<String> bad = new ArrayList<>();
        int programs = 0, lPairs = 0, overPairs = 0, refPairs = 0, underPairs = 0, may = 0, notCtx = 0, notCtxRef = 0;
        int balancedPairs = 0, balancedMayBad = 0;
        for (String p : E6Reference.programs()) {
            PTAScene.junitReset();
            PTA pta = run(p, "insens");
            Map<Node, Set<AllocNode>> ref = E6Reference.fieldsReference(pta);
            Map<Node, Set<AllocNode>> bounded = E3UcfsPointsToTest.normalize(
                    new E6Reference.CsModel(pta).boundedPairs(DEPTH, MAX_STATES));
            IdrGraph g = IdrExport.export(pta, IdrCalls.CS);
            IdrResult r = IdrSolve.solve(g, "parity");
            Map<Node, Set<AllocNode>> under = pts(g, r.getUnder());
            Map<Node, Set<AllocNode>> over = pts(g, r.getOver());
            IdrGraph gb = IdrExport.export(pta, IdrCalls.BALANCED);
            IdrResult rb = IdrSolve.solve(gb, "parity");
            Map<Node, Set<AllocNode>> balancedUnder = pts(gb, rb.getUnder());
            Map<Node, Set<AllocNode>> balancedOver = pts(gb, rb.getOver());

            check(bad, p + ": bounded CS pairs not in over", E3UcfsPointsToTest.minus(bounded, over));
            check(bad, p + ": under not in over", E3UcfsPointsToTest.minus(under, over));
            check(bad, p + ": over not in the FIELDS reference", E3UcfsPointsToTest.minus(over, ref));
            check(bad, p + ": bounded CS pairs not in the FIELDS reference", E3UcfsPointsToTest.minus(bounded, ref));
            check(bad, p + ": BALANCED under not in CS over", E3UcfsPointsToTest.minus(balancedUnder, over));
            check(bad, p + ": BALANCED over not in the FIELDS reference", E3UcfsPointsToTest.minus(balancedOver, ref));

            boolean context = p.startsWith(E6Reference.CONTEXT);
            for (E3UcfsPointsToTest.AliasQuery q : E3UcfsPointsToTest.queries(pta)) {
                if (q.mayAlias()) {
                    may++;
                    if (!E3UcfsPointsToTest.ucfsAlias(pta, over, q)) {
                        bad.add(p + ": mayAlias(" + q.a() + ", " + q.b() + ") does not hold in the CS over-approximation");
                    }
                    if (!E3UcfsPointsToTest.ucfsAlias(pta, balancedOver, q)) {
                        balancedMayBad++;
                    }
                } else if (context) {
                    notCtx++;
                    if (E3UcfsPointsToTest.ucfsAlias(pta, over, q)) {
                        bad.add(p + ": notAlias(" + q.a() + ", " + q.b() + ") does not hold in the CS over-approximation");
                    }
                    if (E3UcfsPointsToTest.ucfsAlias(pta, ref, q)) {
                        notCtxRef++;
                    }
                }
            }
            programs++;
            lPairs += E3UcfsPointsToTest.pairs(bounded);
            overPairs += E3UcfsPointsToTest.pairs(over);
            underPairs += E3UcfsPointsToTest.pairs(under);
            refPairs += E3UcfsPointsToTest.pairs(ref);
            balancedPairs += E3UcfsPointsToTest.pairs(balancedOver);
            System.out.println("E6IdrCsTest " + p + " bounded=" + E3UcfsPointsToTest.pairs(bounded) + " under="
                    + E3UcfsPointsToTest.pairs(under) + " over=" + E3UcfsPointsToTest.pairs(over) + " ref="
                    + E3UcfsPointsToTest.pairs(ref) + " balancedOver=" + E3UcfsPointsToTest.pairs(balancedOver)
                    + " times=" + r.getTimes() + " " + g.getCounters());
        }
        System.out.println("E6IdrCsTest total: programs=" + programs + " bounded=" + lPairs + " under=" + underPairs
                + " over=" + overPairs + " ref=" + refPairs + " balancedOver=" + balancedPairs + " mayAlias=" + may
                + " balancedMayAliasViolated=" + balancedMayBad + " contextNotAlias=" + notCtx
                + " contextNotAliasViolatedByRef=" + notCtxRef);
        assertEquals(61, programs);
        assertTrue("the context programs have notAlias assertions: " + notCtx, notCtx >= 18);
        assertTrue("the CI reference violates some notAlias of the context programs", notCtxRef > 0);
        assertTrue("CS removes pairs of the CI reference: over " + overPairs + " < ref " + refPairs, overPairs < refPairs);
        assertTrue("the fully balanced export loses mayAlias facts that CS keeps: " + balancedMayBad, balancedMayBad > 0);
        assertTrue(String.join("\n", bad.subList(0, Math.min(30, bad.size()))), bad.isEmpty());
    }

    /** The vertex an edge into node enters in layer F or B: X_IN for a context-insensitive variable. */
    private static int into(IdrGraph g, Node n, Layer l) {
        int in = g.idOf(new IdrVertex(n, l == Layer.F ? Layer.F_IN : Layer.B_IN));
        return in >= 0 ? in : g.idOf(new IdrVertex(n, l));
    }

    private static void check(List<String> bad, String what, List<Node[]> diff) {
        if (!diff.isEmpty()) {
            bad.add(what + ": " + diff.size() + ", e.g. " + diff.get(0)[0] + " <- " + diff.get(0)[1]);
        }
    }

    /**
     * Shape of the CS graph (E6.md D5, D6): each call edge of the call graph from an invoke statement
     * with a reference argument and parameter is an `op--c` edge F(argument) -> F(parameter), and
     * `cp--c` B(parameter) -> B(argument), where c is the index of the statement in IdrGraph.sites;
     * returns are `cp--c` F(return) -> F(result) and `op--c` B(result) -> B(return) (an edge into a
     * context-insensitive variable X enters X_IN instead of X); START vertices
     * have only `op` self-loops and one `normal` edge to their object; END vertices only `cp`
     * self-loops and one `normal` edge from F of their variable; a context-insensitive variable X
     * (every global) has F_IN -normal-> F and B_IN -normal-> B, `cp` self-loops on F_IN/B_IN and
     * `op` self-loops on F/B, and its answer vertex is F_IN; no other parenthesis self-loops; the
     * other edges go between the layers their label allows (FIELDS table plus the gadget edges).
     */
    @Test
    public void csGraphShape() {
        List<String> bad = new ArrayList<>();
        for (String p : E6Reference.programs()) {
            PTAScene.junitReset();
            PTA pta = run(p, "insens");
            IdrGraph g = IdrExport.export(pta, IdrCalls.CS);
            Set<String> edges = new HashSet<>();
            Map<Integer, List<LabeledEdge>> out = new HashMap<>();
            for (LabeledEdge e : g.getEdges()) {
                edges.add(e.getFrom() + " " + e.getLabel() + " " + e.getTo());
                out.computeIfAbsent(e.getFrom(), k -> new ArrayList<>()).add(e);
                Matcher m = E6IdrFieldsTest.LABEL.matcher(e.getLabel());
                if (!m.matches()) {
                    bad.add(p + ": label " + e.getLabel());
                    continue;
                }
                if ("p".equals(m.group(2)) && (Integer.parseInt(m.group(3)) >= g.getSites().size() || !m.group(4).isEmpty())) {
                    bad.add(p + ": site id " + e.getLabel() + " >= " + g.getSites().size());
                }
                Layer a = g.getVertices().get(e.getFrom()).getLayer();
                Layer b = g.getVertices().get(e.getTo()).getLayer();
                boolean paren = "p".equals(m.group(2));
                if (e.getFrom() == e.getTo() && paren) {
                    boolean ok = (a == Layer.START && e.getLabel().startsWith("op--"))
                            || (a == Layer.END && e.getLabel().startsWith("cp--"))
                            || ((a == Layer.F_IN || a == Layer.B_IN) && e.getLabel().startsWith("cp--"))
                            || ((a == Layer.F || a == Layer.B) && e.getLabel().startsWith("op--")
                            && g.idOf(new IdrVertex(g.getVertices().get(e.getFrom()).getNode(),
                            a == Layer.F ? Layer.F_IN : Layer.B_IN)) >= 0);
                    if (!ok) {
                        bad.add(p + ": self-loop " + e.getLabel() + " on " + a + " " + g.getVertices().get(e.getFrom()).getNode());
                    }
                } else {
                    String kind = e.getLabel().equals("normal") ? "normal" : paren ? "paren" : m.group(1) + "b" + m.group(4);
                    boolean ok = switch (kind) {
                        case "normal" -> List.of("OBJ>F", "OBJ>F_IN", "F>F", "F>F_IN", "B>B", "B>B_IN", "B>OBJ",
                                "START>OBJ", "F>END", "F_IN>F", "B_IN>B").contains(a + ">" + b);
                        case "ob", "cbr" -> a == Layer.F && (b == Layer.B || b == Layer.B_IN);
                        case "cb" -> a == Layer.F && (b == Layer.F || b == Layer.F_IN);
                        case "obr" -> a == Layer.B && (b == Layer.B || b == Layer.B_IN);
                        case "paren" -> (a == Layer.F && (b == Layer.F || b == Layer.F_IN))
                                || (a == Layer.B && (b == Layer.B || b == Layer.B_IN));
                        default -> false;
                    };
                    if (!ok) {
                        bad.add(p + ": " + e.getLabel() + " from " + a + " to " + b);
                    }
                }
            }
            for (int i = 0; i < g.getVertices().size(); i++) {
                IdrVertex v = g.getVertices().get(i);
                List<LabeledEdge> os = out.getOrDefault(i, List.of());
                if (v.getLayer() == Layer.START) {
                    long normals = os.stream().filter(e -> e.getLabel().equals("normal")).count();
                    if (normals != 1 || g.sourceVertex((AllocNode) v.getNode()) != i
                            || !edges.contains(i + " normal " + g.idOf(new IdrVertex(v.getNode(), Layer.OBJ)))) {
                        bad.add(p + ": START of " + v.getNode());
                    }
                }
                if (v.getLayer() == Layer.END) {
                    final int end = i;
                    int f = g.idOf(new IdrVertex(v.getNode(), Layer.F));
                    if (!edges.contains(f + " normal " + i) || g.answerVertex((VarNode) v.getNode()) != i
                            || os.stream().anyMatch(e -> e.getTo() != end)) {
                        bad.add(p + ": END of " + v.getNode());
                    }
                }
                if (v.getNode() instanceof GlobalVarNode gv && v.getLayer() == Layer.F) {
                    int fin = g.idOf(new IdrVertex(gv, Layer.F_IN));
                    int bin = g.idOf(new IdrVertex(gv, Layer.B_IN));
                    int b = g.idOf(new IdrVertex(gv, Layer.B));
                    if (fin < 0 || b < 0 || bin < 0 || !edges.contains(fin + " normal " + i)
                            || !edges.contains(bin + " normal " + b) || g.answerVertex(gv) != fin) {
                        bad.add(p + ": erasure gadget of " + gv);
                    }
                }
            }
            // call edges per site, independently of the exporter
            for (E6Reference.CallEdge c : E6Reference.callEdges(pta)) {
                int site = g.getSites().indexOf(c.site());
                int fu = g.idOf(new IdrVertex(c.from(), Layer.F));
                int fw = into(g, c.to(), Layer.F);
                int bu = into(g, c.from(), Layer.B);
                int bw = g.idOf(new IdrVertex(c.to(), Layer.B));
                String fwd = c.entry() ? "op--" : "cp--";
                String bwd = c.entry() ? "cp--" : "op--";
                if (site < 0 || !edges.contains(fu + " " + fwd + site + " " + fw) || !edges.contains(bw + " " + bwd + site + " " + bu)) {
                    bad.add(p + ": call edge " + c.from() + " -> " + c.to() + (c.entry() ? " entry" : " exit") + " at " + c.site());
                }
            }
        }
        assertTrue(String.join("\n", bad.subList(0, Math.min(30, bad.size()))), bad.isEmpty());
    }
}
