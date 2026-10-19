package qilin.ucfs

import qilin.core.PTA
import qilin.core.PointsToAnalysis
import qilin.core.pag.AllocNode
import qilin.core.pag.ContextField
import qilin.core.pag.FieldRefNode
import qilin.core.pag.LocalVarNode
import qilin.core.pag.Node
import qilin.core.pag.Parm
import qilin.core.pag.VarNode
import soot.Unit as SootUnit
import soot.jimple.spark.pag.SparkField

/** Builds the UCFS input graph from the global PAG of a finished Qilin analysis (E3-S1, E3-S3b). */
object PagExport {

    /**
     * Turns the global PAG of [pta] into a labeled graph over dense vertex ids for UCFS
     * (E3.md D1-D4). Call it after `pta.run()` or `pta.pureRun()` has returned; the edges come
     * from [QilinPagSeam.globalEdges].
     *
     * D1, what is dropped: each edge with an end in a `ContextField` (the node `o.f`). The solver
     * adds those edges itself in `Solver.handleStoreEdge`/`Solver.handleLoadEdge`, for the
     * objects `o` it has already found in the points-to set of the base, so they are a result of
     * the analysis that ran (Spark for `-pta=insens`; E2.md R5). Keeping them would hand UCFS the
     * field part of the answer.
     *
     * D1, what is kept although the solver made it from points-to sets: some `new` edges of the
     * map `PAG.getAlloc()` are also a result of the analysis, and they are exported as they are:
     * - receiver object -> `this` of the dispatched callee (`CallGraphBuilder.addVirtualEdge`);
     * - thrown object -> the variable of the catching handler, or the throw node of the method
     *   when no handler of the method catches it (`ExceptionHandler.dispatch`);
     * - object -> parameter of `java.lang.ref.Finalizer.register`
     *   (`Solver.handleImplicitCallToFinalizerRegister`).
     * The edge ROOT object -> `this` of the fake main (`CallGraphBuilder.getEntryPoints`) is kept
     * too; it binds the entry point and is not read from a points-to set (E3.md D13).
     * So in this mode `pts(this)` and the flow of exception objects come from Spark, and UCFS
     * solves the field and copy part on top of them. Argument -> parameter and return -> result
     * `assign` edges follow the call graph that Spark built on the fly (`processCallAssign`).
     *
     * D2, why the receiver binding comes from the analysis: this is the pipeline "Kernel +
     * Solver[low-cost] => UCFS", where a cheap Spark run goes first and UCFS works on its
     * result. Eagle does the same, it takes `pts(this)` from the pre-analysis Spark
     * (`qilin.pta.toolkits.eagle.Eagle`, `prePTA.reachingObjects(thisRef)`). The mode without the
     * receiver edges into `this` is `export(pta, ReceiverBinding.CALL_GRAPH)` (E3-S3b).
     *
     * This is the mode [ReceiverBinding.ANALYSIS].
     *
     * D3, CI projection: a `ContextVarNode` or `ContextAllocNode` becomes its `base()`, and so
     * does the base variable of a `FieldRefNode`; another node type at an end of a kept edge is
     * an error (`IllegalArgumentException`). Edges of different contexts that project to the
     * same CI edge become one edge. Under `insens` a method has one (empty) context, so the
     * projection should merge nothing there (interpretation, E3.md D3). For other `-pta`
     * patterns this gives the projection of their graph, which E3 does not test.
     *
     * D4, labels and orientation (`Sridharan2005Demand`, p. 4-5; strings in [PtLabels]):
     * - `o -new-> v` for `AllocNode o -> VarNode v`, `u -assign-> v` for a copy `u -> v`;
     * - `x.f = y` (`y -> x.f` in the PAG) gives `y -store_i-> x`: from the stored value to the base;
     * - `z = x.f` (`x.f -> z` in the PAG) gives `x -load_i-> z`: from the base to the result;
     *   here `i` is the dense index of the field `f`. The Qilin PAG models array elements as the
     *   one field `ArrayElement` and a static field as a `GlobalVarNode` with `assign` edges, so
     *   a static field gets a vertex and no field index;
     * - each edge `u -l-> v` is also added reversed as `v -bar(l)-> u` ([PtLabels.bar]), for the
     *   reversed flowsTo of the alias part of the grammar.
     *
     * Vertex ids and field indices are given in the order the nodes and fields first occur on a
     * kept edge, so a vertex lies on some edge and a field is used by some load or store edge.
     * The edge list holds no repeated edge.
     */
    @JvmStatic
    fun export(pta: PTA): UcfsGraph = export(pta, ReceiverBinding.ANALYSIS)

    /**
     * Turns the global PAG of [pta] into a UCFS input graph with the receiver binding [binding]
     * (E3.md D15). With [ReceiverBinding.ANALYSIS] the result is the graph of `export(pta)`
     * (D1-D4 there).
     *
     * With [ReceiverBinding.CALL_GRAPH] the graph differs from `export(pta)` in the edges into
     * `this` nodes:
     * - removed: each `new` edge object -> `this` of a method (a `LocalVarNode` whose variable is
     *   the `this` `Parm`), except the edge from the ROOT object (`PTA.getRootNode()`) to `this`
     *   of the fake main (`CallGraphBuilder.getEntryPoints`), which has no receiver variable and
     *   stays. In qilin.core, edges into `this` nodes are added by `CallGraphBuilder.addVirtualEdge`
     *   and `getEntryPoints`; the statements of a method read its `this` (`r0 := @this`) and do
     *   not write it. So the removed edges are the receiver edges that `addVirtualEdge` added
     *   from the points-to set of the receiver;
     * - added: `r -assign-> this(m)` (with its reversed `assign_bar`), for each edge of the CI
     *   call graph of the analysis (`PTA.getCallGraph()`, Spark's on-the-fly call graph for
     *   `-pta=insens`) out of a call site that the solver recorded as an instance call site
     *   (`CallGraphBuilder.getReceiverToSitesMap()`) into a non-static method `m`; `r` is the CI
     *   projection of the receiver variable of that site (`VirtualCallSite.recNode()`, the base
     *   of the Jimple invoke) and `this(m)` the CI `this` node of `m`. An `assign` edge already
     *   in the PAG is not added twice.
     *
     * Not changed by the mode: the call graph (which methods a site calls, the argument ->
     * parameter and return -> result `assign` edges of `CallGraphBuilder.processCallAssign`) and
     * the exception edges thrown object -> catch variable or throw node
     * (`ExceptionHandler.dispatch`) are Spark's in both modes, and so is the edge into the
     * parameter of `java.lang.ref.Finalizer.register`. UCFS computes `pts(this)` in this mode;
     * without the dispatch filter of the solver the answer can grow (E3.md, class R3).
     * Precedent: `Sridharan2005Demand` (p. 9), with a fixed call graph (CHA there) and the
     * parameters and returns of a call as `assign` edges.
     *
     * Throws `IllegalStateException` if a call edge out of a recorded instance call site leads
     * to a non-static method without a `this` node in the PAG.
     */
    @JvmStatic
    fun export(pta: PTA, binding: ReceiverBinding): UcfsGraph {
        val vertices = ArrayList<Node>()
        val vertexIds = HashMap<Node, Int>()
        val fields = ArrayList<SparkField>()
        val fieldIds = HashMap<SparkField, Int>()
        val edges = LinkedHashSet<LabeledEdge>()

        fun vertex(node: Node): Int {
            val ci = ci(node)
            return vertexIds.getOrPut(ci) { vertices.add(ci); vertices.size - 1 }
        }

        fun field(f: SparkField): Int = fieldIds.getOrPut(f) { fields.add(f); fields.size - 1 }

        fun add(from: Node, label: String, to: Node) {
            val u = vertex(from)
            val v = vertex(to)
            edges.add(LabeledEdge(u, label, v))
            edges.add(LabeledEdge(v, PtLabels.bar(label), u))
        }

        val bindByCallGraph = binding == ReceiverBinding.CALL_GRAPH
        val root = pta.rootNode.base()

        for (e in QilinPagSeam.globalEdges(pta)) {
            if (e.from is ContextField || e.to is ContextField) {
                continue
            }
            when (e.kind) {
                PagEdgeKind.NEW -> {
                    if (bindByCallGraph && isThis(ci(e.to)) && ci(e.from) != root) {
                        continue
                    }
                    add(e.from, PtLabels.NEW, e.to)
                }
                PagEdgeKind.ASSIGN -> add(e.from, PtLabels.ASSIGN, e.to)
                PagEdgeKind.LOAD -> {
                    val fr = e.from as FieldRefNode
                    add(fr.base, PtLabels.load(field(fr.field)), e.to)
                }
                PagEdgeKind.STORE -> {
                    val fr = e.to as FieldRefNode
                    add(e.from, PtLabels.store(field(fr.field)), fr.base)
                }
            }
        }
        if (bindByCallGraph) {
            for ((receiver, thisNode) in receiverAssigns(pta)) {
                add(receiver, PtLabels.ASSIGN, thisNode)
            }
        }
        return UcfsGraph(edges.toList(), vertices, fields)
    }

    /**
     * Pairs (receiver variable, `this` of the callee), CI, for the call edges of
     * [ReceiverBinding.CALL_GRAPH], without repeats. The order follows the iteration order of
     * `PTA.getCallGraph()`, so it does not depend on the hash order of the receiver map.
     */
    private fun receiverAssigns(pta: PTA): List<Pair<Node, Node>> {
        val pag = pta.pag
        val receiversOf = HashMap<SootUnit, LinkedHashSet<Node>>()
        for ((recNode, sites) in pta.cgb.receiverToSitesMap) {
            for (site in sites) {
                receiversOf.getOrPut(site.unit) { LinkedHashSet() }.add(ci(recNode))
            }
        }
        val out = LinkedHashSet<Pair<Node, Node>>()
        for (edge in pta.callGraph) {
            val receivers = receiversOf[edge.srcUnit() ?: continue] ?: continue
            val callee = edge.tgt()
            if (callee.isStatic) {
                continue
            }
            val thisNode = pag.findLocalVarNode(Parm(callee, PointsToAnalysis.THIS_NODE))
                ?: throw IllegalStateException("no this node of the callee $callee of the call edge $edge")
            receivers.forEach { out.add(it to thisNode) }
        }
        return out.toList()
    }

    private fun isThis(node: Node): Boolean = node is LocalVarNode && node.isThis

    /** CI projection (D3): a variable or object node becomes its `base()`. */
    private fun ci(node: Node): Node = when (node) {
        is VarNode -> node.base()
        is AllocNode -> node.base()
        else -> throw IllegalArgumentException("not a variable or object node: $node (${node.javaClass.name})")
    }
}
