package qilin.pta.ucfs;

import qilin.CoreConfig;
import qilin.core.pag.AllocNode;
import qilin.core.pag.ArrayElement;
import qilin.core.pag.LocalVarNode;
import qilin.core.pag.Node;
import qilin.core.pag.VarNode;
import qilin.ucfs.LabeledEdge;
import qilin.ucfs.PtLabels;
import qilin.ucfs.UcfsGraph;
import qilin.util.PTAUtils;
import soot.ArrayType;
import soot.RefType;
import soot.Type;
import soot.jimple.CastExpr;
import soot.jimple.spark.pag.SparkField;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.BitSet;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.BiPredicate;

/**
 * The reference fixpoint of the comparison {@link UcfsCompare} (E4-S3, E3.md D16): the
 * field-sensitive Andersen fixpoint over the forward edges of a {@link UcfsGraph} (labels
 * {@code new}, {@code assign}, {@code store_i}, {@code load_i} of {@link PtLabels}; the reversed
 * {@code _bar} edges are not read), with the filters of Qilin's solver switched on or off
 * ({@link Filters}). Without filters it is the language L_FT of UCFS on the same graph (flowsTo of
 * {@code Sridharan2005Demand} is Andersen as CFL-reachability); with all filters it repeats the
 * filters of the propagation of {@code qilin.core.solver.Solver} listed below, on the edges of the
 * graph (whether that gives Spark's answer is checked outside, E4.md D5).
 *
 * <p>Rules, for a store {@code y -store_f-> x} ({@code x.f = y}) and a load {@code x -load_f-> z}
 * ({@code z = x.f}): for each object {@code b} in {@code pts(x)}, {@code pts(b.f)} gets
 * {@code pts(y)} and {@code pts(z)} gets {@code pts(b.f)}; {@code b.f} is a field node of the CI
 * object {@code b} (the graph is a CI projection, E3.md D3). The filters, each as the solver does
 * it:
 * <ul>
 *   <li>{@link Filters#invisible()}: these objects never enter a set (their {@code new} edges are
 *       not seeded). For the solver these are the objects whose PAG node has number 0, which
 *       {@code HybridPointsToSet} reads as an empty slot: the ROOT object (E3.md R4b);</li>
 *   <li>{@link Filters#declaredTypes()}: an object {@code o} enters the set of a variable that is
 *       not a cast node, or of a field node, only if {@code PTAUtils.castNeverFails(o.getType(),
 *       type)} (the test of {@code PTAUtils.addWithTypeFiltering} in {@code Solver.propagatePTS});
 *       the type of a variable is its declared type, the type of a field node is the one
 *       {@code ContextField} gives it ({@link #fieldNodeType});</li>
 *   <li>{@link Filters#castTypes()}: the same test at cast nodes (a {@code LocalVarNode} whose
 *       variable is a {@code CastExpr}), with the cast type;</li>
 *   <li>{@link Filters#emptyArrays()}: no store and no load through a base object that is an empty
 *       array ({@code PTAUtils.isEmptyArray}, {@code Solver.disallowStoreOrLoadOn}).</li>
 * </ul>
 * The fixpoint is computed by difference propagation over node ids: the vertices of the graph and,
 * after them, the field nodes made on the fly; a store or load through a new base object adds a
 * copy edge to or from the field node.
 */
final class ReferenceFixpoint {

    /** Which filters of the solver are on; see the class comment. */
    record Filters(Set<AllocNode> invisible, boolean declaredTypes, boolean castTypes, boolean emptyArrays) {
        static final Filters NONE = new Filters(Set.of(), false, false, false);
    }

    private static final String STORE_PREFIX = "store_";
    private static final String LOAD_PREFIX = "load_";

    private final UcfsGraph graph;
    private final int nVertices;
    /** Vertex id -> dense object index, -1 for a vertex that is not an object. */
    private final int[] objIndex;
    private final List<AllocNode> objects = new ArrayList<>();

    private final List<BitSet> pts = new ArrayList<>();
    private final List<BitSet> delta = new ArrayList<>();
    private final List<TypeFilter> filterOf = new ArrayList<>();
    private final List<List<Integer>> succ = new ArrayList<>();
    private final Set<Long> copyEdges = new HashSet<>();
    private final Map<Long, Integer> fieldNodes = new HashMap<>();
    private final Map<Type, TypeFilter> filterByType = new HashMap<>();
    private final ArrayDeque<Integer> work = new ArrayDeque<>();
    private final BitSet queued = new BitSet();

    /** x -> {y, f} for y -store_f-> x; x -> {f, z} for x -load_f-> z. */
    private final Map<Integer, List<int[]>> storesByBase = new HashMap<>();
    private final Map<Integer, List<int[]>> loadsByBase = new HashMap<>();

    private final Filters filters;

    /**
     * Solves the fixpoint of {@code graph} with {@code filters}, without the {@code new} edges
     * {@code o -> v} for which {@code dropNew.test(o, v)} holds.
     */
    ReferenceFixpoint(UcfsGraph graph, Filters filters, BiPredicate<Node, Node> dropNew) {
        this.graph = graph;
        this.filters = filters;
        this.nVertices = graph.getVertices().size();
        this.objIndex = new int[nVertices];
        for (int v = 0; v < nVertices; v++) {
            Node n = graph.nodeOf(v);
            if (n instanceof AllocNode o) {
                objIndex[v] = objects.size();
                objects.add(o);
            } else {
                objIndex[v] = -1;
            }
            newNode(n instanceof VarNode var ? variableFilter(var) : null);
        }
        List<int[]> news = new ArrayList<>();
        for (LabeledEdge e : graph.getEdges()) {
            String l = e.getLabel();
            if (l.endsWith(PtLabels.BAR_SUFFIX)) {
                continue;
            }
            int u = e.getFrom();
            int v = e.getTo();
            if (l.equals(PtLabels.NEW)) {
                news.add(new int[]{u, v});
            } else if (l.equals(PtLabels.ASSIGN)) {
                addCopy(u, v);
            } else if (l.startsWith(STORE_PREFIX)) {
                int f = Integer.parseInt(l.substring(STORE_PREFIX.length()));
                storesByBase.computeIfAbsent(v, k -> new ArrayList<>()).add(new int[]{u, f});
            } else if (l.startsWith(LOAD_PREFIX)) {
                int f = Integer.parseInt(l.substring(LOAD_PREFIX.length()));
                loadsByBase.computeIfAbsent(u, k -> new ArrayList<>()).add(new int[]{f, v});
            } else {
                throw new IllegalArgumentException("unknown edge label " + l + " in " + e);
            }
        }
        for (int[] e : news) {
            AllocNode o = (AllocNode) graph.nodeOf(e[0]);
            if (filters.invisible().contains(o) || dropNew.test(o, graph.nodeOf(e[1]))) {
                continue;
            }
            BitSet one = new BitSet();
            one.set(objIndex[e[0]]);
            flow(e[1], one);
        }
        solve();
    }

    /** As {@link #ReferenceFixpoint(UcfsGraph, Filters, BiPredicate)} with all {@code new} edges. */
    ReferenceFixpoint(UcfsGraph graph, Filters filters) {
        this(graph, filters, (o, v) -> false);
    }

    /** Whether {@code obj} is in the set of the CI variable {@code var}; false if either is not a vertex. */
    boolean contains(VarNode var, AllocNode obj) {
        int v = graph.vertexOf(var);
        int o = graph.vertexOf(obj);
        return v >= 0 && o >= 0 && objIndex[o] >= 0 && pts.get(v).get(objIndex[o]);
    }

    /** The number of pairs (variable, object) over the variable vertices of the graph (field nodes not counted). */
    long pairCount() {
        long n = 0;
        for (int v = 0; v < nVertices; v++) {
            if (graph.nodeOf(v) instanceof VarNode) {
                n += pts.get(v).cardinality();
            }
        }
        return n;
    }

    private void solve() {
        while (!work.isEmpty()) {
            int n = work.poll();
            queued.clear(n);
            BitSet d = delta.get(n);
            delta.set(n, new BitSet());
            if (n < nVertices) {
                for (int[] yf : storesByBase.getOrDefault(n, List.of())) {
                    for (int b = d.nextSetBit(0); b >= 0; b = d.nextSetBit(b + 1)) {
                        if (accessAllowed(b)) {
                            int fn = fieldNode(b, yf[1]);
                            if (addCopy(yf[0], fn)) {
                                flow(fn, pts.get(yf[0]));
                            }
                        }
                    }
                }
                for (int[] fz : loadsByBase.getOrDefault(n, List.of())) {
                    for (int b = d.nextSetBit(0); b >= 0; b = d.nextSetBit(b + 1)) {
                        if (accessAllowed(b)) {
                            int fn = fieldNode(b, fz[0]);
                            if (addCopy(fn, fz[1])) {
                                flow(fz[1], pts.get(fn));
                            }
                        }
                    }
                }
            }
            List<Integer> out = succ.get(n);
            for (int i = 0; i < out.size(); i++) {
                flow(out.get(i), d);
            }
        }
    }

    /** Adds to the set of node {@code to} the objects of {@code objs} that pass its filter. */
    private void flow(int to, BitSet objs) {
        BitSet add = (BitSet) objs.clone();
        add.andNot(pts.get(to));
        if (add.isEmpty()) {
            return;
        }
        TypeFilter f = filterOf.get(to);
        if (f != null) {
            for (int o = add.nextSetBit(0); o >= 0; o = add.nextSetBit(o + 1)) {
                if (!f.passes(o)) {
                    add.clear(o);
                }
            }
            if (add.isEmpty()) {
                return;
            }
        }
        pts.get(to).or(add);
        delta.get(to).or(add);
        if (!queued.get(to)) {
            queued.set(to);
            work.add(to);
        }
    }

    private boolean addCopy(int from, int to) {
        if (!copyEdges.add(((long) from << 32) | to)) {
            return false;
        }
        succ.get(from).add(to);
        return true;
    }

    private boolean accessAllowed(int obj) {
        return !(filters.emptyArrays() && PTAUtils.isEmptyArray(objects.get(obj).base()));
    }

    private int fieldNode(int obj, int field) {
        long key = ((long) obj << 32) | field;
        Integer id = fieldNodes.get(key);
        if (id == null) {
            Type t = filters.declaredTypes() ? fieldNodeType(objects.get(obj), graph.getFields().get(field)) : null;
            id = newNode(t == null ? null : filterByType.computeIfAbsent(t, TypeFilter::new));
            fieldNodes.put(key, id);
        }
        return id;
    }

    private int newNode(TypeFilter filter) {
        pts.add(new BitSet());
        delta.add(new BitSet());
        filterOf.add(filter);
        succ.add(new ArrayList<>());
        return pts.size() - 1;
    }

    private TypeFilter variableFilter(VarNode var) {
        boolean cast = var instanceof LocalVarNode lv && lv.getVariable() instanceof CastExpr;
        if (cast ? !filters.castTypes() : !filters.declaredTypes()) {
            return null;
        }
        return filterByType.computeIfAbsent(var.getType(), TypeFilter::new);
    }

    /**
     * The type of the field node {@code base.f}, as {@code ContextField} computes it: {@code Object}
     * without {@code -pae} ({@code preciseArrayElement}), the element type of the base's array type
     * for the array element field, the declared type of the field otherwise. {@code ContextField}
     * throws for an array element of a base object that is not an array; the solver never makes
     * such a node, because the base variable of an array access has an array type. A reference step
     * with the declared types on but the cast types off can still let such an object through a
     * cast node; for it the reference takes the field's own type ({@code Object} for
     * {@code ArrayElement}), so it does not filter there (a choice of this reference, not the
     * solver's behavior).
     */
    static Type fieldNodeType(AllocNode base, SparkField f) {
        if (!CoreConfig.v().getPtaConfig().preciseArrayElement) {
            return RefType.v("java.lang.Object");
        }
        if (f instanceof ArrayElement && base.getType() instanceof ArrayType at) {
            return at.getArrayElementType();
        }
        return f.getType();
    }

    /** {@code PTAUtils.castNeverFails(o.getType(), type)} per object index, each object tested once. */
    private final class TypeFilter {
        private final Type type;
        private final BitSet tested = new BitSet();
        private final BitSet passed = new BitSet();

        TypeFilter(Type type) {
            this.type = type;
        }

        boolean passes(int obj) {
            if (!tested.get(obj)) {
                tested.set(obj);
                if (PTAUtils.castNeverFails(objects.get(obj).getType(), type)) {
                    passed.set(obj);
                }
            }
            return passed.get(obj);
        }
    }
}
