package qilin.pta.ucfs;

import qilin.core.pag.AllocNode;
import qilin.core.pag.GlobalVarNode;
import qilin.core.pag.LocalVarNode;
import qilin.core.pag.Node;
import qilin.core.pag.Parm;
import qilin.core.pag.ValNode;
import qilin.core.pag.VarNode;
import qilin.pta.PTAConfig;
import qilin.pta.tools.UcfsPTA;
import qilin.stat.SimplifiedEvaluator;
import qilin.ucfs.LabeledEdge;
import qilin.ucfs.PagExport;
import qilin.ucfs.PtLabels;
import qilin.ucfs.ReceiverBinding;
import qilin.ucfs.UcfsGraph;
import qilin.util.PTAUtils;
import soot.jimple.CaughtExceptionRef;

import java.io.File;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.BiPredicate;

/**
 * Same-run comparison of the views of a {@link UcfsPTA} (E4-S3, E4.md D5, D7, D15): the metrics of
 * Qilin per view, every pair (variable, object) of Spark or UCFS with a class of the difference, and
 * the share of the UCFS answer that the Spark kernel seeded. Called by driver.Main when the option
 * {@code -ucfscompare} is set (only with {@code -pta=ucfs}), after {@code pta.run()}.
 *
 * <p><b>Pairs and classes</b> ({@link #pairs}). A pair is a CI variable and a CI object. Its flags:
 * in Spark (the view SPARK, {@link UcfsPTA#pointsTo}), in UCFS ({@link UcfsPTA#getUcfsAnswer()},
 * with ROOT), in UCFS_TYPED. A pair of both is SAME, a pair of Spark only is MISSING. A pair of UCFS
 * only gets the class of the first step below whose reference fixpoint ({@link ReferenceFixpoint})
 * does not hold it; the steps switch the filters of Qilin's solver on one by one:
 * <ol>
 *   <li>R3, only for {@link ReceiverBinding#CALL_GRAPH}: no filter, on the export
 *       {@code PagExport.export(pta, ANALYSIS)}, where {@code pts(this)} comes from the dispatch of
 *       the solver instead of the receiver variables;</li>
 *   <li>R4b: the objects whose solver node has number 0 (ROOT) are invisible;</li>
 *   <li>R1: + the declared types of the variables other than cast nodes and of the field nodes;</li>
 *   <li>R2: + the cast types of the cast nodes;</li>
 *   <li>R5: + no store or load through an empty array.</li>
 * </ol>
 * The steps R4b..R5 run on the export with {@link ReceiverBinding#ANALYSIS}: {@link UcfsPTA#getUcfsGraph()}
 * for that binding, {@code PagExport.export(pta, ANALYSIS)} for CALL_GRAPH. A pair that the last
 * step still holds is UNEXPLAINED: none of these filters removes it. The class does not read the
 * answer of Spark, only the flag S does. The order of the steps is a convention (E3.md D16, with R3
 * first): a pair that two filters remove each alone gets the class of the earlier step; the declared
 * type comes before the cast type because a cast node is a special typed variable.
 *
 * <p>The last step has all the filters of the solver on the edges that Spark solved, so when the
 * classification is complete its pairs are Spark's pairs ({@code last-step-pairs} below). The
 * pts of the field nodes are not compared: UCFS does not compute them (the edges into {@code o.f}
 * are not exported, see {@link PagExport}).
 *
 * <p><b>Seeds</b> ({@link #counters}, E4.md D15). A seed is a forward {@code new} edge o -> v of
 * {@link UcfsPTA#getUcfsGraph()} with o not the ROOT object ({@code getRootNode().base()}) and v the
 * {@code this} of a method ({@code LocalVarNode.isThis()}; kind this), a throw node
 * ({@code Parm.isThrowRet()}) or the variable of a {@code CaughtExceptionRef} (kind exception), or the
 * parameter 0 of {@code <java.lang.ref.Finalizer: void register(java.lang.Object)>} (kind
 * finalizer). The kind is read from the node v only. Qilin's solver writes such edges from the
 * points-to sets of Spark ({@code CallGraphBuilder.addVirtualEdge}, {@code ExceptionHandler.dispatch},
 * {@code Solver.handleImplicitCallToFinalizerRegister}; E3.md D1), not the allocation statements.
 * The counters say how many there are and how many SAME pairs the reference without filters on the
 * same graph still finds without them.
 */
public final class UcfsCompare {
    private UcfsCompare() {
    }

    /** The metric lines of {@link SimplifiedEvaluator} in {@code metrics.tsv}, in this order. */
    public static final List<String> METRICS = List.of(
            "#Reachable Method (CI):", "#Call Edge(CI):", "#May Fail Cast (Total):",
            "#Virtual Call Site(Polymorphic):", "#globalAlias_incstst:",
            "#Avg Points-to Target without Native Var(CI):");

    /** The classes of a pair, in the order of the printed lines. */
    public static final List<String> CLASSES = List.of(
            "SAME", "R3", "R4b", "R1", "R2", "R5", "UNEXPLAINED", "MISSING");

    /** The counters of {@link #counters}, in this order. */
    public static final List<String> COUNTERS = List.of(
            "new-edges", "seed-this-edges", "seed-exception-edges", "seed-finalizer-edges",
            "same-without-this-seeds", "same-without-seeds", "last-step-pairs");

    /** The views in the columns of {@code metrics.tsv} and of the values of {@link #metrics}. */
    private static final UcfsPTA.View[] VIEWS = {UcfsPTA.View.SPARK, UcfsPTA.View.UCFS, UcfsPTA.View.UCFS_TYPED};

    private static final String FINALIZER_REGISTER = "<java.lang.ref.Finalizer: void register(java.lang.Object)>";

    /**
     * One pair (CI variable, CI object) of Spark or UCFS.
     *
     * @param inSpark the object is in the view SPARK of the variable
     * @param inUcfs  the object is in {@link UcfsPTA#getUcfsAnswer()} of the variable (ROOT included)
     * @param inTyped the object is in the view UCFS_TYPED of the variable
     * @param cls     one of {@link #CLASSES}
     */
    public record PairRow(VarNode var, AllocNode obj, boolean inSpark, boolean inUcfs, boolean inTyped, String cls) {
    }

    private enum Seed { THIS, EXCEPTION, FINALIZER }

    /** One step of the classification: the class it gives and its reference fixpoint's input. */
    private record Step(String cls, UcfsGraph graph, ReferenceFixpoint.Filters filters) {
    }

    // ------------------------------------------------------------------------------ metrics

    /**
     * The values of the lines {@link #METRICS} that Qilin's {@link SimplifiedEvaluator} prints on
     * {@code pta} in each view: key = metric line, value = {SPARK, UCFS, UCFS_TYPED}, each the value
     * string as the evaluator prints it. The evaluator is run once per view, with the view of
     * {@code pta} switched; the view of {@code pta} is restored afterwards.
     */
    public static Map<String, String[]> metrics(UcfsPTA pta) {
        UcfsPTA.View saved = pta.getView();
        Map<String, String[]> out = new LinkedHashMap<>();
        for (String k : METRICS) {
            out.put(k, new String[VIEWS.length]);
        }
        try {
            for (int i = 0; i < VIEWS.length; i++) {
                pta.setView(VIEWS[i]);
                Map<String, String> printed = evaluate(pta);
                for (String k : METRICS) {
                    String v = printed.get(k);
                    if (v == null) {
                        throw new IllegalStateException("SimplifiedEvaluator printed no line " + k);
                    }
                    out.get(k)[i] = v;
                }
            }
        } finally {
            pta.setView(saved);
        }
        return out;
    }

    /** The lines "#name: value" of a SimplifiedEvaluator run on {@code pta} in its current view. */
    private static Map<String, String> evaluate(UcfsPTA pta) {
        SimplifiedEvaluator ev = new SimplifiedEvaluator(pta);
        ev.begin();
        ev.end();
        Map<String, String> m = new HashMap<>();
        for (String line : ev.toString().split("\n")) {
            int i = line.indexOf(':');
            if (line.startsWith("#") && i > 0) {
                m.put(line.substring(0, i + 1), line.substring(i + 1).trim());
            }
        }
        return m;
    }

    // ------------------------------------------------------------------------------ pairs

    /**
     * Every pair (CI variable, CI object) of Spark or of UCFS, once, with its flags and class (see
     * the class comment). The variables are the CI projections of the variable nodes of the PAG
     * ({@code LocalVarNode}, {@code GlobalVarNode}) and the variables of {@link UcfsPTA#getUcfsAnswer()}.
     * Ordered by the labels ({@link PTAUtils#getNodeLabel}) of the variable and the object.
     */
    public static List<PairRow> pairs(UcfsPTA pta) {
        if (pta.getUcfsGraph() == null) {
            throw new IllegalStateException("no UCFS graph: the analysis has not run");
        }
        Map<VarNode, Set<AllocNode>> answer = pta.getUcfsAnswer();
        Set<VarNode> vars = new LinkedHashSet<>();
        for (ValNode n : pta.getPag().getValNodeNumberer()) {
            if (n instanceof VarNode v && (v.base() instanceof LocalVarNode || v.base() instanceof GlobalVarNode)) {
                vars.add(v.base());
            }
        }
        vars.addAll(answer.keySet());

        List<Object[]> rows = new ArrayList<>(); // {var, obj, S, U, T, cls or null}
        for (VarNode v : vars) {
            Set<AllocNode> s = pta.pointsTo(v, UcfsPTA.View.SPARK);
            Set<AllocNode> u = answer.getOrDefault(v, Set.of());
            Set<AllocNode> t = pta.pointsTo(v, UcfsPTA.View.UCFS_TYPED);
            Set<AllocNode> all = new LinkedHashSet<>(s);
            all.addAll(u);
            for (AllocNode o : all) {
                boolean inS = s.contains(o);
                boolean inU = u.contains(o);
                String cls = inS && inU ? "SAME" : inS ? "MISSING" : null;
                rows.add(new Object[]{v, o, inS, inU, t.contains(o), cls});
            }
        }

        List<Object[]> pending = new ArrayList<>();
        for (Object[] r : rows) {
            if (r[5] == null) {
                pending.add(r);
            }
        }
        for (Step step : steps(pta)) {
            if (pending.isEmpty()) {
                break;
            }
            ReferenceFixpoint fp = new ReferenceFixpoint(step.graph(), step.filters());
            List<Object[]> kept = new ArrayList<>();
            for (Object[] r : pending) {
                if (fp.contains((VarNode) r[0], (AllocNode) r[1])) {
                    kept.add(r);
                } else {
                    r[5] = step.cls();
                }
            }
            pending = kept;
        }
        for (Object[] r : pending) {
            r[5] = "UNEXPLAINED";
        }

        List<PairRow> out = new ArrayList<>(rows.size());
        for (Object[] r : rows) {
            out.add(new PairRow((VarNode) r[0], (AllocNode) r[1], (Boolean) r[2], (Boolean) r[3], (Boolean) r[4], (String) r[5]));
        }
        out.sort(Comparator.comparing((PairRow r) -> PTAUtils.getNodeLabel(r.var()))
                .thenComparing(r -> PTAUtils.getNodeLabel(r.obj())));
        return out;
    }

    /** The steps of the classification in their order (class comment), the last one with all filters. */
    private static List<Step> steps(UcfsPTA pta) {
        boolean byCallGraph = pta.getBinding() == ReceiverBinding.CALL_GRAPH;
        UcfsGraph analysis = byCallGraph ? PagExport.export(pta, ReceiverBinding.ANALYSIS) : pta.getUcfsGraph();
        Set<AllocNode> invisible = invisibleObjects(pta);
        List<Step> steps = new ArrayList<>();
        if (byCallGraph) {
            steps.add(new Step("R3", analysis, ReferenceFixpoint.Filters.NONE));
        }
        steps.add(new Step("R4b", analysis, new ReferenceFixpoint.Filters(invisible, false, false, false)));
        steps.add(new Step("R1", analysis, new ReferenceFixpoint.Filters(invisible, true, false, false)));
        steps.add(new Step("R2", analysis, new ReferenceFixpoint.Filters(invisible, true, true, false)));
        steps.add(new Step("R5", analysis, new ReferenceFixpoint.Filters(invisible, true, true, true)));
        return steps;
    }

    /**
     * The CI objects whose node in the solver has number 0. {@code HybridPointsToSet} reads the
     * number 0 as an empty slot, so these never enter a points-to set of Spark; under insens this is
     * the ROOT object, which {@code PTA} creates without a numberer (E3.md R4b).
     */
    private static Set<AllocNode> invisibleObjects(UcfsPTA pta) {
        Set<AllocNode> s = new HashSet<>();
        for (AllocNode a : pta.getPag().getAlloc().keySet()) {
            if (a.getNumber() == 0) {
                s.add(a.base());
            }
        }
        return s;
    }

    // ------------------------------------------------------------------------------ counters

    /**
     * The counters {@link #COUNTERS}, in this order (class comment, "Seeds"):
     * <ul>
     *   <li>{@code new-edges}: the forward {@code new} edges of {@link UcfsPTA#getUcfsGraph()};</li>
     *   <li>{@code seed-this-edges}, {@code seed-exception-edges}, {@code seed-finalizer-edges}: the
     *       seeds among them, per kind;</li>
     *   <li>{@code same-without-this-seeds}, {@code same-without-seeds}: the rows SAME of
     *       {@code rows} whose pair the reference fixpoint without filters on the same graph holds
     *       without the seeds of kind this, and without all seeds;</li>
     *   <li>{@code last-step-pairs}: the pairs (CI variable, CI object) of the last step of the
     *       classification (all filters, R5).</li>
     * </ul>
     *
     * @param rows {@code pairs(pta)}
     */
    public static Map<String, Integer> counters(UcfsPTA pta, List<PairRow> rows) {
        UcfsGraph g = pta.getUcfsGraph();
        if (g == null) {
            throw new IllegalStateException("no UCFS graph: the analysis has not run");
        }
        AllocNode root = pta.getRootNode().base();
        int news = 0;
        Map<Seed, Integer> seeds = new java.util.EnumMap<>(Seed.class);
        for (Seed k : Seed.values()) {
            seeds.put(k, 0);
        }
        for (LabeledEdge e : g.getEdges()) {
            if (e.getLabel().equals(PtLabels.NEW)) {
                news++;
                Seed k = seedKind(root, g.nodeOf(e.getFrom()), g.nodeOf(e.getTo()));
                if (k != null) {
                    seeds.merge(k, 1, Integer::sum);
                }
            }
        }
        BiPredicate<Node, Node> thisSeed = (o, v) -> seedKind(root, o, v) == Seed.THIS;
        BiPredicate<Node, Node> anySeed = (o, v) -> seedKind(root, o, v) != null;
        ReferenceFixpoint noThis = new ReferenceFixpoint(g, ReferenceFixpoint.Filters.NONE, thisSeed);
        ReferenceFixpoint noSeeds = new ReferenceFixpoint(g, ReferenceFixpoint.Filters.NONE, anySeed);
        int keptThis = 0;
        int keptAll = 0;
        for (PairRow r : rows) {
            if (r.cls().equals("SAME")) {
                keptThis += noThis.contains(r.var(), r.obj()) ? 1 : 0;
                keptAll += noSeeds.contains(r.var(), r.obj()) ? 1 : 0;
            }
        }
        List<Step> steps = steps(pta);
        Step last = steps.get(steps.size() - 1);
        long lastPairs = new ReferenceFixpoint(last.graph(), last.filters()).pairCount();

        Map<String, Integer> out = new LinkedHashMap<>();
        out.put("new-edges", news);
        out.put("seed-this-edges", seeds.get(Seed.THIS));
        out.put("seed-exception-edges", seeds.get(Seed.EXCEPTION));
        out.put("seed-finalizer-edges", seeds.get(Seed.FINALIZER));
        out.put("same-without-this-seeds", keptThis);
        out.put("same-without-seeds", keptAll);
        out.put("last-step-pairs", Math.toIntExact(lastPairs));
        return out;
    }

    /** The kind of the seed {@code o -new-> v}, by the node {@code v}; null if it is not a seed. */
    private static Seed seedKind(AllocNode root, Node o, Node v) {
        if (o.equals(root) || !(v instanceof LocalVarNode lv)) {
            return null;
        }
        if (lv.isThis()) {
            return Seed.THIS;
        }
        Object var = lv.getVariable();
        if ((var instanceof Parm p && p.isThrowRet()) || var instanceof CaughtExceptionRef) {
            return Seed.EXCEPTION;
        }
        if (var instanceof Parm p && p.getIndex() == 0 && p.method().getSignature().equals(FINALIZER_REGISTER)) {
            return Seed.FINALIZER;
        }
        return null;
    }

    // ------------------------------------------------------------------------------ CLI

    /**
     * The comparison of a finished run of {@code -pta=ucfs} (driver.Main, {@code -ucfscompare}).
     * Writes into {@code <outDir>/ucfs-compare} ({@code outDir} of {@code PTAConfig}):
     * <ul>
     *   <li>{@code metrics.tsv}: the header {@code metric<TAB>SPARK<TAB>UCFS<TAB>UCFS_TYPED} and one
     *       line per metric of {@link #METRICS}, in order, with the values of {@link #metrics};</li>
     *   <li>{@code pairs.tsv}: {@code var<TAB>object<TAB>S<TAB>U<TAB>T<TAB>class} per row of
     *       {@link #pairs}; the labels are {@link PTAUtils#getNodeLabel} of the CI nodes (as in
     *       {@code vertices.tsv} of {@code -ucfspt}), the flags 0/1.</li>
     * </ul>
     * Prints the lines {@code #UCFS-cmp-<k>: <v>}, each once: {@code binding}, {@code spark-pairs},
     * {@code ucfs-pairs}, {@code typed-pairs} (rows with the flag S, U, T), one per class of
     * {@link #CLASSES} in that order (0 included), one per counter of {@link #COUNTERS} in that
     * order. The metric lines themselves are not printed again.
     */
    public static void run(UcfsPTA pta) {
        List<PairRow> rows = pairs(pta);
        Map<String, String[]> metrics = metrics(pta);
        Map<String, Integer> counters = counters(pta, rows);

        File dir = new File(PTAConfig.v().getOutConfig().outDir, "ucfs-compare");
        if (!dir.isDirectory() && !dir.mkdirs()) {
            throw new UncheckedIOException(new IOException("cannot create directory " + dir));
        }
        List<String> mlines = new ArrayList<>();
        mlines.add("metric\tSPARK\tUCFS\tUCFS_TYPED");
        metrics.forEach((k, v) -> mlines.add(k + "\t" + String.join("\t", v)));
        write(new File(dir, "metrics.tsv"), mlines);
        List<String> plines = new ArrayList<>(rows.size());
        for (PairRow r : rows) {
            plines.add(PTAUtils.getNodeLabel(r.var()) + "\t" + PTAUtils.getNodeLabel(r.obj()) + "\t" + flag(r.inSpark())
                    + "\t" + flag(r.inUcfs()) + "\t" + flag(r.inTyped()) + "\t" + r.cls());
        }
        write(new File(dir, "pairs.tsv"), plines);

        Map<String, Integer> byClass = new LinkedHashMap<>();
        for (String c : CLASSES) {
            byClass.put(c, 0);
        }
        int spark = 0;
        int ucfs = 0;
        int typed = 0;
        for (PairRow r : rows) {
            byClass.merge(r.cls(), 1, Integer::sum);
            spark += r.inSpark() ? 1 : 0;
            ucfs += r.inUcfs() ? 1 : 0;
            typed += r.inTyped() ? 1 : 0;
        }
        System.out.println("#UCFS-cmp-binding: " + pta.getBinding());
        System.out.println("#UCFS-cmp-spark-pairs: " + spark);
        System.out.println("#UCFS-cmp-ucfs-pairs: " + ucfs);
        System.out.println("#UCFS-cmp-typed-pairs: " + typed);
        byClass.forEach((c, n) -> System.out.println("#UCFS-cmp-" + c + ": " + n));
        counters.forEach((k, n) -> System.out.println("#UCFS-cmp-" + k + ": " + n));
    }

    private static String flag(boolean b) {
        return b ? "1" : "0";
    }

    private static void write(File file, List<String> lines) {
        try {
            Files.write(file.toPath(), lines, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
