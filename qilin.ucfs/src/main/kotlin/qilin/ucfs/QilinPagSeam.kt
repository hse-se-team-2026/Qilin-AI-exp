package qilin.ucfs

import qilin.core.PTA
import qilin.core.pag.Node

/**
 * Kind of an edge of the global pointer assignment graph (PAG) of Qilin. Each kind is one of the
 * four edge maps of [qilin.core.pag.PAG]; edges point in the direction values flow.
 */
enum class PagEdgeKind {
    /** `AllocNode -> VarNode`, map `PAG.getAlloc()`: the variable may hold the object. */
    NEW,

    /** `ValNode -> ValNode`, map `PAG.getSimple()`: a copy; either end can be a `ContextField` (`o.f`). */
    ASSIGN,

    /** `FieldRefNode -> VarNode`, map `PAG.getLoad()`: `y = x.f` (an array element is the field `ArrayElement`). */
    LOAD,

    /** `VarNode -> FieldRefNode`, map `PAG.getStoreInv()` read in reverse: `x.f = y` (array elements as for [LOAD]). */
    STORE,
}

/** One edge `from -> to` of the global PAG, as stored by Qilin (nodes are not copied). */
data class PagEdge(val kind: PagEdgeKind, val from: Node, val to: Node)

/**
 * Seam between the Qilin kernel + solver and the UCFS side: reads the graph the finished
 * pointer analysis left in [PTA.getPag].
 */
object QilinPagSeam {
    /**
     * Returns the edges of the global PAG of [pta], read from the maps `alloc` ([PagEdgeKind.NEW]),
     * `simple` ([PagEdgeKind.ASSIGN]), `load` ([PagEdgeKind.LOAD]) and `storeInv`
     * ([PagEdgeKind.STORE], turned into `VarNode -> FieldRefNode`) of `pta.getPag()`.
     * Each (key, value) pair of a map gives one edge, so on the same PAG the count per kind
     * equals the matching counter of `qilin.stat.PAGStat` (`#Alloc-pag-edge`, `#Simple-pag-edge`,
     * `#Load-pag-edge`, `#Store-pag-edge`).
     *
     * Call it after `pta.run()` or `pta.pureRun()` has returned. The solver adds edges to these
     * maps while it propagates, so a call before that sees only the edges added so far.
     *
     * The maps hold the internal edges of `MethodPAG` (per method, without contexts) of the
     * reachable non-phantom methods, parameterized by `Solver.addToPAG` with the context of each
     * reachable method-context pair (an edge from an allocation into a `GlobalVarNode` gets the
     * empty context, `PAG.addGlobalPAGEdge`). They also hold edges that the kernel adds while
     * solving, outside `Solver.addToPAG`. In qilin.core these come from, among others:
     * - `CallGraphBuilder.addVirtualEdge`: receiver object -> `this` of the dispatched callee;
     * - `CallGraphBuilder.processCallAssign`: argument -> parameter and return value -> the
     *   variable receiving the call result (with `-pe`, also the callee's throw node -> a throw
     *   variable of the call site);
     * - `Solver.handleStoreEdge` / `Solver.handleLoadEdge`: `x -> o.f` and `o.f -> y` for the
     *   objects `o` in the points-to set of the base variable (except those that
     *   `Solver.disallowStoreOrLoadOn` rejects), where `o.f` is a `ContextField` (an ASSIGN edge,
     *   since `ContextField` is a `ValNode`);
     * - `CallGraphBuilder.getEntryPoints` (ROOT object -> `this` of the fake main),
     *   `ExceptionHandler` (thrown object -> parameter of the catching handler, or the method's
     *   throw node) and
     *   `Solver.handleImplicitCallToFinalizerRegister` (object -> parameter of `Finalizer.register`).
     *
     * Warning (E2.md R5): part of this graph is a result of the points-to analysis that ran
     * (Spark for `-pta=insens`). The edges into `this` and across calls follow the call graph
     * that the solver builds on the fly, and `handleStoreEdge`/`handleLoadEdge` add `o.f` edges
     * for the objects `o` already found in the base's points-to set. A CFL solver given the whole
     * graph partly re-derives those results. The node types are kept, so a caller can select a
     * subset (for example, drop the edges touching a `ContextField`).
     */
    @JvmStatic
    fun globalEdges(pta: PTA): Set<PagEdge> {
        val pag = pta.pag
        val edges = LinkedHashSet<PagEdge>()
        for ((heap, vars) in pag.alloc) {
            vars.forEach { edges.add(PagEdge(PagEdgeKind.NEW, heap, it)) }
        }
        for ((src, dsts) in pag.simple) {
            dsts.forEach { edges.add(PagEdge(PagEdgeKind.ASSIGN, src, it)) }
        }
        for ((fieldRef, vars) in pag.load) {
            vars.forEach { edges.add(PagEdge(PagEdgeKind.LOAD, fieldRef, it)) }
        }
        for ((fieldRef, vars) in pag.storeInv) {
            vars.forEach { edges.add(PagEdge(PagEdgeKind.STORE, it, fieldRef)) }
        }
        return edges
    }
}
