package qilin.ucfs

/**
 * How [PagExport.export] binds the receiver of an instance call to `this` of the callee
 * (E3.md B1, D2, D15).
 *
 * In both modes the call graph is the CI call graph of the analysis that ran
 * (`PTA.getCallGraph()`, Spark's on-the-fly call graph for `-pta=insens`), and so are the
 * argument -> parameter and return -> result `assign` edges and the exception edges
 * (`ExceptionHandler.dispatch`). The modes differ in the edges into `this` nodes.
 */
enum class ReceiverBinding {
    /**
     * Main mode (E3-S1, D2), the same graph as `PagExport.export(pta)`: the `new` edges
     * receiver object -> `this` of the dispatched callee that the solver added from the points-to
     * set of the receiver (`CallGraphBuilder.addVirtualEdge`) are exported as they are, so
     * `pts(this)` comes from the analysis.
     */
    ANALYSIS,

    /**
     * Second mode (E3-S3b, D15). The `new` edges into `this` nodes are not exported, except
     * ROOT object -> `this` of the fake main (`CallGraphBuilder.getEntryPoints`; the entry point
     * has no receiver variable). Instead, for each edge of the CI call graph of the analysis
     * (`PTA.getCallGraph()`) out of an instance call site recorded by the solver
     * (`CallGraphBuilder.getReceiverToSitesMap()`) into a non-static method, there is an edge
     * receiver variable -assign-> `this` of the callee. UCFS then computes `pts(this)` itself;
     * the call graph that chose the callees and the exception edges are still the analysis's.
     *
     * Binding by the variable has no dispatch filter: `this` of every callee of a site gets the
     * whole points-to set of the receiver variable, not only the objects that dispatch to that
     * callee. So the answer can grow compared to [ANALYSIS] (class R3 of E3.md).
     *
     * Precedent: `Sridharan2005Demand` (p. 9) also fixes the call graph first (there by CHA) and
     * models the parameters and returns of a call as `assign` edges.
     */
    CALL_GRAPH,
}
