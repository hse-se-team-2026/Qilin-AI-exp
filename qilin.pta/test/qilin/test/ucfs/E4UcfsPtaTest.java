package qilin.test.ucfs;

import static org.junit.Assert.assertTrue;

import driver.PTAPattern;
import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.junit.Test;
import qilin.core.PTA;
import qilin.core.PTAScene;
import qilin.core.pag.AllocNode;
import qilin.core.pag.GlobalVarNode;
import qilin.core.pag.LocalVarNode;
import qilin.core.pag.MethodPAG;
import qilin.core.pag.Node;
import qilin.core.pag.VarNode;
import qilin.core.builder.MethodNodeFactory;
import qilin.pta.PTAConfig;
import qilin.pta.tools.UcfsPTA;
import qilin.stat.SimplifiedEvaluator;
import qilin.test.util.JunitTests;
import qilin.ucfs.ReceiverBinding;
import qilin.util.PTAUtils;
import soot.Local;
import soot.RefLikeType;
import soot.SootField;
import soot.SootMethod;
import soot.Type;
import soot.Unit;
import soot.Value;
import soot.jimple.AssignStmt;
import soot.jimple.CastExpr;
import soot.options.Options;

/**
 * E4-S1 acceptance check (docs/ai/tickets/E4-S1.md): the analysis qilin.pta.tools.UcfsPTA, whose
 * points-to sets are the answer of UCFS on the exported PAG of its Spark kernel.
 *
 * <p>Oracles, computed here and not by UcfsPTA, on the 43 small programs of E3
 * (E3UcfsPointsToTest.PROGRAMS), for both receiver bindings:
 * <ol>
 *   <li>view UCFS = Andersen without filters on the input of the binding (REF of E3-S3 for
 *       ANALYSIS, REF2 of E3-S3b for CALL_GRAPH), without the ROOT object; the number of dropped
 *       pairs with ROOT = the number of ROOT pairs of that reference (at least 1: this of the fake
 *       main method);</li>
 *   <li>view UCFS_TYPED = that set, kept only for objects whose type passes
 *       PTAUtils.castNeverFails(object type, variable type);</li>
 *   <li>view SPARK = Andersen with all filters of Qilin's solver (REF_T of E3-S3, equal to Spark
 *       on these programs), for both bindings (the kernel is the same Spark run);</li>
 *   <li>the query methods agree: reachingObjects(Node), reachingObjects(Local) and, for static
 *       fields, reachingObjects(SootField) return the set of the view; the accessor
 *       pointsTo(v, view) returns the set of the view it is asked for, whatever the current view;</li>
 *   <li>Qilin's own evaluator (SimplifiedEvaluator) on the analysis reads the view: its may-fail
 *       casts and average points-to equal a recomputation here over the expected sets of the view,
 *       and its call-graph lines do not depend on the view.</li>
 * </ol>
 */
public class E4UcfsPtaTest extends JunitTests {

    private static final String P = E3UcfsPointsToTest.P;

    /** Runs UcfsPTA (insens kernel) on {@code mainClass}, as JunitTests.run does for createPTA. */
    static UcfsPTA runUcfs(String mainClass, ReceiverBinding binding) {
        PTAConfig.v().getAppConfig().MAIN_CLASS = mainClass;
        Options.v().set_main_class(mainClass);
        PTAScene.v().setMainClass(PTAScene.v().getSootClass(mainClass));
        PTAConfig.v().getPtaConfig().ptaPattern = new PTAPattern("insens");
        PTAConfig.v().getPtaConfig().ptaName = PTAConfig.v().getPtaConfig().ptaPattern.toString();
        UcfsPTA pta = new UcfsPTA(binding);
        pta.pureRun();
        return pta;
    }

    static Map<Node, Set<AllocNode>> withoutRoot(Map<Node, Set<AllocNode>> ref, AllocNode root) {
        Map<Node, Set<AllocNode>> m = new HashMap<>();
        ref.forEach((v, objs) -> {
            Set<AllocNode> s = new HashSet<>(objs);
            s.remove(root);
            if (!s.isEmpty()) {
                m.put(v, s);
            }
        });
        return m;
    }

    static Map<Node, Set<AllocNode>> typed(Map<Node, Set<AllocNode>> m) {
        Map<Node, Set<AllocNode>> r = new HashMap<>();
        m.forEach((v, objs) -> {
            Set<AllocNode> s = new HashSet<>();
            for (AllocNode o : objs) {
                if (PTAUtils.castNeverFails(o.getType(), v.getType())) {
                    s.add(o);
                }
            }
            if (!s.isEmpty()) {
                r.put(v, s);
            }
        });
        return r;
    }

    static Set<AllocNode> ciSet(qilin.core.sets.PointsToSet s) {
        Set<AllocNode> out = new HashSet<>();
        for (AllocNode o : s.toCollection()) {
            out.add(o.base());
        }
        return out;
    }

    /** The points-to map the query methods of pta return for every CI variable, in the current view. */
    static Map<Node, Set<AllocNode>> viewByNode(PTA pta, Set<Node> vars) {
        Map<Node, Set<AllocNode>> m = new HashMap<>();
        for (Node v : vars) {
            Set<AllocNode> s = ciSet(pta.reachingObjects(v));
            if (!s.isEmpty()) {
                m.put(v, s);
            }
        }
        return m;
    }

    /** pta.pointsTo(v, view) for every CI variable, without empty sets. */
    static Map<Node, Set<AllocNode>> byAccessor(UcfsPTA pta, Set<Node> vars, UcfsPTA.View view) {
        Map<Node, Set<AllocNode>> m = new HashMap<>();
        for (Node v : vars) {
            Set<AllocNode> s = new HashSet<>();
            for (AllocNode o : pta.pointsTo((VarNode) v, view)) {
                s.add(o.base());
            }
            if (!s.isEmpty()) {
                m.put(v, s);
            }
        }
        return m;
    }

    /** Disagreements of reachingObjects(Local) and reachingObjects(SootField) with {@code expected}. */
    static List<String> otherQueries(PTA pta, Set<Node> vars, Map<Node, Set<AllocNode>> expected) {
        List<String> bad = new ArrayList<>();
        for (Node v : vars) {
            Set<AllocNode> exp = expected.getOrDefault(v, Set.of());
            if (v instanceof LocalVarNode lv && lv.getVariable() instanceof Local l) {
                Set<AllocNode> got = ciSet(pta.reachingObjects(l));
                if (!got.equals(exp) && bad.size() < 3) {
                    bad.add("reachingObjects(Local " + l + ") " + got + " != " + exp);
                }
            } else if (v instanceof GlobalVarNode gv && gv.getVariable() instanceof SootField f && f.isStatic()) {
                Set<AllocNode> got = ciSet(pta.reachingObjects(f));
                if (!got.equals(exp) && bad.size() < 3) {
                    bad.add("reachingObjects(SootField " + f + ") " + got + " != " + exp);
                }
            }
        }
        return bad;
    }

    // ------------------------------------------------------------------ metrics, recomputed here
    @SuppressWarnings("unchecked")
    static Set<String> handledNatives() throws Exception {
        Field f = SimplifiedEvaluator.class.getDeclaredField("handledNatives");
        f.setAccessible(true);
        return (Set<String>) f.get(new SimplifiedEvaluator(null));
    }

    /** {mayFailCasts, avgPointsTo} over {@code pts} (CI variable -> CI objects), as SimplifiedEvaluator defines them. */
    static double[] metrics(PTA pta, Map<Node, Set<AllocNode>> pts) throws Exception {
        Set<SootMethod> reachable = new HashSet<>();
        pta.getCgb().getReachableMethods().forEach(m -> reachable.add(m.method()));
        int mayFail = 0;
        for (SootMethod sm : reachable) {
            for (Unit u : PTAUtils.getMethodBody(sm).getUnits()) {
                if (u instanceof AssignStmt as && as.getRightOp() instanceof CastExpr ce
                        && as.getLeftOp().getType() instanceof RefLikeType && ce.getOp() instanceof Local op) {
                    Type target = ce.getCastType();
                    LocalVarNode n = pta.getPag().findLocalVarNode(op);
                    for (AllocNode o : pts.getOrDefault(n, Set.of())) {
                        if (!PTAUtils.castNeverFails(o.getType(), target)) {
                            mayFail++;
                            break;
                        }
                    }
                }
            }
        }
        Set<LocalVarNode> vars = new HashSet<>();
        for (Local l : pta.getPag().getLocalPointers()) {
            if (!l.toString().contains("intermediate/")) {
                vars.add(pta.getPag().findLocalVarNode(l));
            }
        }
        for (SootMethod sm : pta.getNakedReachableMethods()) {
            MethodPAG mpag = pta.getPag().getMethodPAG(sm);
            MethodNodeFactory mnf = mpag.nodeFactory();
            if (!sm.isStatic()) {
                vars.add((LocalVarNode) mnf.caseThis());
            }
            for (int i = 0; i < sm.getParameterCount(); ++i) {
                if (sm.getParameterType(i) instanceof RefLikeType) {
                    vars.add((LocalVarNode) mnf.caseParm(i));
                }
            }
        }
        Set<String> natives = handledNatives();
        long sum = 0;
        long cnt = 0;
        for (LocalVarNode v : vars) {
            if (v == null || PTAUtils.isFakeMainMethod(v.getMethod()) || natives.contains(v.getMethod().toString())) {
                continue;
            }
            Set<Object> sites = new HashSet<>();
            for (AllocNode o : pts.getOrDefault(v, Set.of())) {
                sites.add(o.getNewExpr());
            }
            if (!sites.isEmpty()) {
                sum += sites.size();
                cnt++;
            }
        }
        return new double[]{mayFail, ((double) sum) / cnt};
    }

    static final String[] CG_LINES = {"#Reachable Method (CI):", "#Call Edge(CI):", "#Virtual Call Site(Polymorphic):"};

    /** metric line -> value printed by SimplifiedEvaluator on pta in its current view */
    static Map<String, String> evaluate(PTA pta) {
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

    // ------------------------------------------------------------------------------ tests
    @Test
    public void viewsAgainstReferencesBothBindings() {
        List<String> failures = new ArrayList<>();
        long[] total = new long[6];
        for (ReceiverBinding b : ReceiverBinding.values()) {
            for (String p : E3UcfsPointsToTest.PROGRAMS) {
                PTAScene.junitReset();
                UcfsPTA pta = runUcfs(P + p, b);
                AllocNode root = pta.getRootNode().base();
                E3UcfsPointsToTest.Edges g = b == ReceiverBinding.ANALYSIS
                        ? new E3UcfsPointsToTest.Edges(pta.getPag()) : E3ReceiverAssignTest.expectedEdges(pta);
                Map<Node, Set<AllocNode>> ref = E3UcfsPointsToTest.andersen(g, E3UcfsPointsToTest.Filters.NONE, true);
                Set<AllocNode> zero = E3UcfsPointsToTest.zeroNumbered(pta.getPag());
                Map<Node, Set<AllocNode>> refT = E3UcfsPointsToTest.andersen(new E3UcfsPointsToTest.Edges(pta.getPag()),
                        new E3UcfsPointsToTest.Filters(zero, true, true, true), true);
                int rootRef = 0;
                for (Set<AllocNode> s : ref.values()) {
                    rootRef += s.contains(root) ? 1 : 0;
                }
                Map<Node, Set<AllocNode>> expU = withoutRoot(ref, root);
                Map<Node, Set<AllocNode>> expT = typed(expU);
                Set<Node> vars = E3UcfsPointsToTest.ciVars(pta.getPag());
                String tag = p + " [" + b + "]";

                pta.setView(UcfsPTA.View.UCFS);
                Map<Node, Set<AllocNode>> gotU = viewByNode(pta, vars);
                if (!gotU.equals(expU)) {
                    failures.add(tag + ": view UCFS != REF without ROOT: " + E3UcfsPointsToTest.diff(gotU, expU));
                }
                failures.addAll(otherQueries(pta, vars, expU).stream().map(s -> tag + " UCFS: " + s).toList());
                if (pta.getRootPairs() != rootRef || rootRef < 1) {
                    failures.add(tag + ": getRootPairs()=" + pta.getRootPairs() + ", ROOT pairs of REF=" + rootRef);
                }
                pta.setView(UcfsPTA.View.UCFS_TYPED);
                Map<Node, Set<AllocNode>> gotT = viewByNode(pta, vars);
                if (!gotT.equals(expT)) {
                    failures.add(tag + ": view UCFS_TYPED != typed REF: " + E3UcfsPointsToTest.diff(gotT, expT));
                }
                failures.addAll(otherQueries(pta, vars, expT).stream().map(s -> tag + " UCFS_TYPED: " + s).toList());
                pta.setView(UcfsPTA.View.SPARK);
                Map<Node, Set<AllocNode>> gotS = viewByNode(pta, vars);
                // the accessor pointsTo(v, view) answers every view whatever the current view is
                pta.setView(UcfsPTA.View.UCFS_TYPED);
                Map<UcfsPTA.View, Map<Node, Set<AllocNode>>> want = Map.of(
                        UcfsPTA.View.UCFS, expU, UcfsPTA.View.UCFS_TYPED, expT, UcfsPTA.View.SPARK, refT);
                for (UcfsPTA.View view : UcfsPTA.View.values()) {
                    Map<Node, Set<AllocNode>> acc = byAccessor(pta, vars, view);
                    if (!acc.equals(want.get(view))) {
                        failures.add(tag + ": pointsTo(v, " + view + ") != reference: " + E3UcfsPointsToTest.diff(acc, want.get(view)));
                    }
                }
                if (!gotS.equals(refT)) {
                    failures.add(tag + ": view SPARK != REF_T: " + E3UcfsPointsToTest.diff(gotS, refT));
                }
                int sparkNotTyped = E3UcfsPointsToTest.minus(gotS, gotT).size();
                int typedNotUcfs = E3UcfsPointsToTest.minus(gotT, gotU).size();
                if (sparkNotTyped != 0 || typedNotUcfs != 0) {
                    failures.add(tag + ": SPARK not in UCFS_TYPED: " + sparkNotTyped + ", UCFS_TYPED not in UCFS: " + typedNotUcfs);
                }
                long[] row = {E3UcfsPointsToTest.pairs(gotU), E3UcfsPointsToTest.pairs(gotT), E3UcfsPointsToTest.pairs(gotS),
                        pta.getRootPairs(), E3UcfsPointsToTest.minus(gotU, gotS).size(), E3UcfsPointsToTest.minus(gotT, gotS).size()};
                for (int i = 0; i < row.length; i++) {
                    total[i] += row[i];
                }
                System.out.println("E4UcfsPtaTest " + tag + ": ucfs=" + row[0] + " typed=" + row[1] + " spark=" + row[2]
                        + " rootPairs=" + row[3] + " ucfsMinusSpark=" + row[4] + " typedMinusSpark=" + row[5]);
            }
        }
        System.out.println("E4UcfsPtaTest total: ucfs=" + total[0] + " typed=" + total[1] + " spark=" + total[2]
                + " rootPairs=" + total[3] + " ucfsMinusSpark=" + total[4] + " typedMinusSpark=" + total[5]);
        assertTrue(String.join("\n", failures), failures.isEmpty());
    }

    @Test
    public void qilinEvaluatorReadsTheView() throws Exception {
        List<String> failures = new ArrayList<>();
        int differs = 0;
        for (ReceiverBinding b : ReceiverBinding.values()) {
            for (String p : E3UcfsPointsToTest.PROGRAMS) {
                PTAScene.junitReset();
                UcfsPTA pta = runUcfs(P + p, b);
                Set<Node> vars = E3UcfsPointsToTest.ciVars(pta.getPag());
                Map<UcfsPTA.View, Map<String, String>> printed = new HashMap<>();
                for (UcfsPTA.View view : UcfsPTA.View.values()) {
                    pta.setView(view);
                    Map<Node, Set<AllocNode>> expected = viewByNode(pta, vars);
                    double[] mine = metrics(pta, expected);
                    Map<String, String> ev = evaluate(pta);
                    printed.put(view, ev);
                    String tag = p + " [" + b + ", " + view + "]";
                    double mayFail = Double.parseDouble(ev.get("#May Fail Cast (Total):"));
                    double avg = Double.parseDouble(ev.get("#Avg Points-to Target without Native Var(CI):"));
                    if (mayFail != mine[0] || Math.abs(avg - mine[1]) > 1e-9) {
                        failures.add(tag + ": evaluator mayFail=" + mayFail + " avg=" + avg
                                + ", recomputed over the view: mayFail=" + mine[0] + " avg=" + mine[1]);
                    }
                }
                for (String line : CG_LINES) {
                    String s = printed.get(UcfsPTA.View.SPARK).get(line);
                    for (UcfsPTA.View view : UcfsPTA.View.values()) {
                        if (s == null || !s.equals(printed.get(view).get(line))) {
                            failures.add(p + " [" + b + "]: " + line + " differs between views SPARK and " + view);
                        }
                    }
                }
                if (!printed.get(UcfsPTA.View.UCFS).equals(printed.get(UcfsPTA.View.SPARK))) {
                    differs++;
                }
            }
        }
        System.out.println("E4UcfsPtaTest evaluator: runs=" + 2 * E3UcfsPointsToTest.PROGRAMS.length
                + " runsWhereUcfsMetricsDifferFromSpark=" + differs);
        assertTrue(String.join("\n", failures), failures.isEmpty());
    }
}
