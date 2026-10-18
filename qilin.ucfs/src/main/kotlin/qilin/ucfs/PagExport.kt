package qilin.ucfs

import qilin.core.PTA
import qilin.core.pag.AllocNode
import qilin.core.pag.ContextField
import qilin.core.pag.FieldRefNode
import qilin.core.pag.Node
import qilin.core.pag.VarNode
import soot.jimple.spark.pag.SparkField

/** Builds the UCFS input graph from the global PAG of a finished Qilin analysis (E3-S1). */
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
     * (`qilin.pta.toolkits.eagle.Eagle`, `prePTA.reachingObjects(thisRef)`). A mode without the
     * edges into `this` is E3-S3b.
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
    fun export(pta: PTA): UcfsGraph {
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

        for (e in QilinPagSeam.globalEdges(pta)) {
            if (e.from is ContextField || e.to is ContextField) {
                continue
            }
            when (e.kind) {
                PagEdgeKind.NEW -> add(e.from, PtLabels.NEW, e.to)
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
        return UcfsGraph(edges.toList(), vertices, fields)
    }

    /** CI projection (D3): a variable or object node becomes its `base()`. */
    private fun ci(node: Node): Node = when (node) {
        is VarNode -> node.base()
        is AllocNode -> node.base()
        else -> throw IllegalArgumentException("not a variable or object node: $node (${node.javaClass.name})")
    }
}
