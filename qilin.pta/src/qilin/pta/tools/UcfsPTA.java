/* Qilin - a Java Pointer Analysis Framework
 * Copyright (C) 2021-2030 Qilin developers
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, either version 3.0 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Lesser Public License for more details.
 *
 * You should have received a copy of the GNU General Lesser Public
 * License along with this program.  If not, see
 * <https://www.gnu.org/licenses/lgpl-3.0.en.html>.
 */

package qilin.pta.tools;

import qilin.core.pag.AllocNode;
import qilin.core.pag.ContextField;
import qilin.core.pag.GlobalVarNode;
import qilin.core.pag.LocalVarNode;
import qilin.core.pag.Node;
import qilin.core.pag.VarNode;
import qilin.core.sets.HybridPointsToSet;
import qilin.core.sets.PointsToSet;
import qilin.core.sets.PointsToSetInternal;
import qilin.core.sets.UnmodifiablePointsToSet;
import qilin.ucfs.PagExport;
import qilin.ucfs.ReceiverBinding;
import qilin.ucfs.UcfsGraph;
import qilin.ucfs.UcfsPointsTo;
import qilin.ucfs.grammar.PointsToGrammar;
import qilin.util.PTAUtils;
import soot.Context;
import soot.Local;
import soot.SootField;
import soot.jimple.spark.pag.SparkField;

import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/**
 * A Qilin analysis whose points-to sets of variables are the answer of UCFS (E4-S1, E4.md D1):
 * {@link #pureRun()} solves the Spark kernel ({@code super.pureRun()}, the context-insensitive
 * {@link Spark}; "Kernel+Solver[low-cost] => UCFS" of the integration plan), exports its global
 * PAG with {@link PagExport#export(qilin.core.PTA, ReceiverBinding)}, solves the language L_FT
 * on it with {@link UcfsPointsTo#solve(UcfsGraph, org.ucfs.grammar.combinator.Grammar)} and
 * {@link PointsToGrammar}, and keeps the map that UCFS returned. The points-to queries of Qilin
 * ({@code reachingObjects}) then answer from that map, so the metrics of Qilin
 * ({@code SimplifiedEvaluator}, {@code PTAEvaluator}) and the {@code -pts} dump, which read
 * variables through {@code reachingObjects} (E4-S1.md, "Контекст"), are computed by the same
 * code as for Spark, over the answer of UCFS.
 *
 * <p>What comes from Spark, by construction (E3.md D2, "Следствие для E4"): the call graph
 * ({@link #getCallGraph()}), the reachable methods and the points-to sets of object fields
 * (the {@code ContextField} nodes {@code o.f}). UCFS does not compute them: the edges into
 * {@code o.f} are not exported ({@link PagExport}, D1 there), and the call graph is the one the
 * Spark solver built on the fly. So the queries that read {@code getP2Set()} of a
 * {@code ContextField} ({@code reachingObjects(ContextField)}, {@code reachingObjects} of an
 * instance field, of a field of a points-to set or of array elements) return the sets of Spark
 * in each view; for a field of a points-to set the bases are matched by their CI object.
 * In the mode {@link ReceiverBinding#ANALYSIS} the {@code new} edges into {@code this}, into
 * catch variables and into the parameter of {@code Finalizer.register} are also made by Spark
 * from its points-to sets (see {@link PagExport}); in {@link ReceiverBinding#CALL_GRAPH} UCFS
 * computes {@code pts(this)} from the receiver variables.
 *
 * <p>The ROOT object ({@link #getRootNode()}{@code .base()}) is not imported: the export keeps
 * the edge ROOT -new-> {@code this} of the fake main, so UCFS finds the pair (that variable,
 * ROOT), which Spark does not show (Qilin numbers the context ROOT object 0, and
 * {@code HybridPointsToSet} reads 0 as an empty slot; E3.md R4b, D13). Its CI object has a
 * non-zero number and would be visible, so the import drops it and counts the dropped pairs in
 * {@link #getRootPairs()}. {@link #getUcfsAnswer()} keeps it.
 *
 * <p>Three views ({@link View}), switched by {@link #setView(View)}, answer the queries:
 * <ul>
 *   <li>{@link View#UCFS}: the answer of UCFS without ROOT;</li>
 *   <li>{@link View#UCFS_TYPED}: the same, where an object {@code o} stays in {@code pts(v)} when
 *       {@code PTAUtils.castNeverFails(o.getType(), v.getType())}: the type filter of Spark
 *       ({@code PTAUtils.addWithTypeFiltering}, {@code qilin.core/src/qilin/util/PTAUtils.java:349-354}),
 *       applied once to the final set of each variable. It is not Spark: Spark applies the filter
 *       at each node while it propagates (also at field nodes and cast nodes), so an object
 *       dropped at a node higher on the path does not reach {@code v} in Spark, while UCFS has no
 *       filter on the path and the final filter at {@code v} can keep it (classes R1/R2 "higher
 *       on the path"; interpretation until the measurements of E4-S6);</li>
 *   <li>{@link View#SPARK}: the kernel's own answer; the queries are those of {@link Spark}.</li>
 * </ul>
 * The kernel is solved once per {@link #pureRun()}, and its answer stays in the PAG nodes, so the
 * three views can be compared within one run (E4.md D7).
 *
 * <p>The sets of the views UCFS and UCFS_TYPED hold CI objects ({@code AllocNode}, not
 * {@code ContextAllocNode}); the set of a {@code ContextVarNode} is the set of its {@code base()}.
 * Under the {@code insens} kernel a method has one context, so this loses nothing
 * (interpretation, E3.md D3).
 */
public class UcfsPTA extends Spark {

    /** Which answer the points-to queries of this analysis return. */
    public enum View {
        /** The answer of UCFS, without the ROOT object. */
        UCFS,
        /** The answer of UCFS without ROOT, with Spark's type filter applied once at each variable. */
        UCFS_TYPED,
        /** The answer of the Spark kernel. */
        SPARK
    }

    private final ReceiverBinding binding;
    private View view = View.UCFS;

    private UcfsGraph ucfsGraph;
    private Map<VarNode, Set<AllocNode>> ucfsAnswer = Collections.emptyMap();
    /** CI variable -> CI objects, as sets of node numbers, per view UCFS and UCFS_TYPED. */
    private Map<VarNode, PointsToSetInternal> ucfsSets = Collections.emptyMap();
    private Map<VarNode, PointsToSetInternal> typedSets = Collections.emptyMap();
    private int rootPairs;
    private long sparkTimeMs;
    private long ucfsTimeMs;

    /** The analysis with the receiver binding {@link ReceiverBinding#ANALYSIS}. */
    public UcfsPTA() {
        this(ReceiverBinding.ANALYSIS);
    }

    /** @param binding how the export binds receivers to {@code this} (see {@link ReceiverBinding}) */
    public UcfsPTA(ReceiverBinding binding) {
        this.binding = binding;
    }

    /**
     * Solves the Spark kernel ({@code super.pureRun()}), then exports its global PAG with the
     * receiver binding of this analysis, runs UCFS on it with {@code PointsToGrammar(k)} for the
     * {@code k} fields of the exported graph and imports the answer into the views UCFS and
     * UCFS_TYPED.
     */
    @Override
    public void pureRun() {
        long t0 = System.currentTimeMillis();
        super.pureRun();
        long t1 = System.currentTimeMillis();
        UcfsGraph graph = PagExport.export(this, binding);
        Map<VarNode, Set<AllocNode>> answer = UcfsPointsTo.solve(graph, new PointsToGrammar(graph.getFields().size()));
        importAnswer(graph, answer);
        long t2 = System.currentTimeMillis();
        sparkTimeMs = t1 - t0;
        ucfsTimeMs = t2 - t1;
    }

    private void importAnswer(UcfsGraph graph, Map<VarNode, Set<AllocNode>> answer) {
        AllocNode root = getRootNode().base();
        Map<VarNode, PointsToSetInternal> plain = new HashMap<>();
        Map<VarNode, PointsToSetInternal> typed = new HashMap<>();
        int roots = 0;
        for (Map.Entry<VarNode, Set<AllocNode>> e : answer.entrySet()) {
            VarNode v = e.getKey();
            PointsToSetInternal p = new HybridPointsToSet();
            PointsToSetInternal t = new HybridPointsToSet();
            for (AllocNode o : e.getValue()) {
                if (o.equals(root)) {
                    roots++;
                    continue;
                }
                if (o.getNumber() == 0) {
                    // HybridPointsToSet reads 0 as an empty slot and would drop the object silently
                    throw new IllegalStateException("object of the UCFS answer without a number: " + o);
                }
                p.add(o.getNumber());
                if (PTAUtils.castNeverFails(o.getType(), v.getType())) {
                    t.add(o.getNumber());
                }
            }
            if (!p.isEmpty()) {
                plain.put(v, p);
            }
            if (!t.isEmpty()) {
                typed.put(v, t);
            }
        }
        this.ucfsGraph = graph;
        this.ucfsAnswer = Collections.unmodifiableMap(answer);
        this.ucfsSets = plain;
        this.typedSets = typed;
        this.rootPairs = roots;
    }

    public ReceiverBinding getBinding() {
        return binding;
    }

    /** The view the points-to queries answer from; {@link View#UCFS} until {@link #setView(View)}. */
    public View getView() {
        return view;
    }

    public void setView(View view) {
        this.view = view;
    }

    /** The graph that UCFS solved in {@link #pureRun()}; {@code null} before it. */
    public UcfsGraph getUcfsGraph() {
        return ucfsGraph;
    }

    /**
     * The map returned by {@code UcfsPointsTo.solve} in {@link #pureRun()}, unchanged and with the
     * ROOT pairs: CI variable -> CI objects. Empty before {@link #pureRun()}.
     */
    public Map<VarNode, Set<AllocNode>> getUcfsAnswer() {
        return ucfsAnswer;
    }

    /** The number of pairs (variable, ROOT object) in the answer of UCFS, which are not imported. */
    public int getRootPairs() {
        return rootPairs;
    }

    /** Wall time of the Spark kernel ({@code super.pureRun()}) in the last {@link #pureRun()}, ms. */
    public long getSparkTimeMs() {
        return sparkTimeMs;
    }

    /** Wall time of the export, the UCFS run and the import in the last {@link #pureRun()}, ms. */
    public long getUcfsTimeMs() {
        return ucfsTimeMs;
    }

    /**
     * The CI objects of the variable {@code ciVar} in {@code view}, whatever the current view is.
     * A context variable is read as its {@code base()}. For {@link View#SPARK} these are the
     * objects of Spark's {@code reachingObjects(ciVar)}, projected with {@code base()}.
     */
    public Set<AllocNode> pointsTo(VarNode ciVar, View view) {
        VarNode v = ciVar.base();
        Set<AllocNode> out = new HashSet<>();
        if (view == View.SPARK) {
            for (AllocNode o : super.reachingObjects(v).toCollection()) {
                out.add(o.base());
            }
            return out;
        }
        PointsToSetInternal s = setsOf(view).get(v);
        if (s != null) {
            for (AllocNode o : new UnmodifiablePointsToSet(this, s).toCollection()) {
                out.add(o);
            }
        }
        return out;
    }

    private Map<VarNode, PointsToSetInternal> setsOf(View view) {
        return view == View.UCFS_TYPED ? typedSets : ucfsSets;
    }

    /** The set of the CI variable {@code v} in the current view (UCFS or UCFS_TYPED), as a copy. */
    private PointsToSet imported(VarNode v) {
        PointsToSetInternal ret = new HybridPointsToSet();
        PointsToSetInternal s = v == null ? null : setsOf(view).get(v.base());
        if (s != null) {
            ret.addAll(s, null);
        }
        return new UnmodifiablePointsToSet(this, ret);
    }

    @Override
    public PointsToSet reachingObjects(Local l) {
        if (view == View.SPARK) {
            return super.reachingObjects(l);
        }
        LocalVarNode v = pag.findLocalVarNode(l);
        return imported(v);
    }

    @Override
    public PointsToSet reachingObjects(Node n) {
        if (view == View.SPARK || n instanceof ContextField) {
            return super.reachingObjects(n);
        }
        return imported((VarNode) n);
    }

    @Override
    public PointsToSet reachingObjects(Context c, Local l) {
        if (view == View.SPARK) {
            return super.reachingObjects(c, l);
        }
        return imported(pag.findContextVarNode(l, c));
    }

    @Override
    public PointsToSet reachingObjects(SootField f) {
        if (view == View.SPARK || !f.isStatic()) {
            return super.reachingObjects(f);
        }
        GlobalVarNode v = pag.findGlobalVarNode(f);
        return imported(v);
    }

    /**
     * Spark's points-to sets of the field {@code f} of the objects in {@code bases}. In the views
     * UCFS and UCFS_TYPED the bases are CI objects, while the bases of the field nodes are context
     * objects, so both are compared by their CI object.
     */
    @Override
    public PointsToSet reachingObjectsInternal(PointsToSet bases, final SparkField f) {
        if (view == View.SPARK) {
            return super.reachingObjectsInternal(bases, f);
        }
        final PointsToSet ciBases = bases.toCIPointsToSet();
        final PointsToSetInternal ret = new HybridPointsToSet();
        pag.getContextFieldVarNodeMap().values().stream().filter(map -> map.containsKey(f)).forEach(map -> {
            ContextField contextField = map.get(f);
            if (ciBases.contains(contextField.getBase().base())) {
                ret.addAll(contextField.getP2Set(), null);
            }
        });
        return new UnmodifiablePointsToSet(this, ret);
    }

    /** As {@link #reachingObjectsInternal(PointsToSet, SparkField)}, for one object. */
    @Override
    public PointsToSet reachingObjectsInternal(AllocNode heap, final SparkField f) {
        if (view == View.SPARK) {
            return super.reachingObjectsInternal(heap, f);
        }
        final AllocNode ciHeap = heap.base();
        final PointsToSetInternal ret = new HybridPointsToSet();
        pag.getContextFieldVarNodeMap().values().stream().filter(map -> map.containsKey(f)).forEach(map -> {
            ContextField contextField = map.get(f);
            if (ciHeap.equals(contextField.getBase().base())) {
                ret.addAll(contextField.getP2Set(), null);
            }
        });
        return new UnmodifiablePointsToSet(this, ret);
    }
}
