package qilin.ucfs

import org.ucfs.grammar.combinator.Grammar
import qilin.core.PTA
import qilin.core.pag.AllocNode
import qilin.core.pag.VarNode
import qilin.ucfs.grammar.PointsToGrammar

/**
 * Context-insensitive points-to sets of a finished Qilin analysis, computed by UCFS (E3-S3):
 * the export of E3-S1 ([PagExport]), the grammar L_FT of E3-S2 ([PointsToGrammar]) and the GLL
 * solver ([UcfsSolver]) started from the object vertices.
 *
 * How the answer relates to Spark (`-pta=insens`), on the graph of [PagExport]:
 * - UCFS applies no type filter. Spark drops an object whose type does not fit the declared type
 *   of a variable or field (R1) or of a cast node (R2), so the answer of UCFS can hold pairs that
 *   Spark does not have. On the 43 programs of `E3UcfsPointsToTest` it holds every CI pair of
 *   Spark (missing=0, checked by `bash acceptance/E3/S3_ucfs_pointsto.sh`); that it is a superset
 *   of Spark on other programs is an expectation, not checked (E3.md R1/R2).
 * - The pair (ROOT, `this` of the fake main method) is in the answer of UCFS and not in Spark:
 *   the export keeps the edge ROOT -new-> `this` of the fake main, while Qilin numbers the ROOT
 *   object 0 and its `HybridPointsToSet` treats 0 as an empty slot (E3.md R4b).
 * - In this mode of the export, `pts(this)` and the flow of exception objects are input from
 *   Spark: the `new` edges receiver -> `this`, thrown object -> catch variable or throw node, and
 *   object -> parameter of `Finalizer.register` were made by the Spark solver from its points-to
 *   sets and are exported as they are ([PagExport], E3.md D1/D2). UCFS solves the copy and field
 *   part on top of them.
 */
object UcfsPointsTo {

    /**
     * Points-to sets of the CI variables of [pta]: `solve(PagExport.export(pta), PointsToGrammar(k))`
     * with `k` the number of fields of the exported graph. Call it after `pta.run()` or
     * `pta.pureRun()` has returned.
     *
     * Keys are CI variables (`LocalVarNode`, `GlobalVarNode`); a variable that no object reaches
     * has no key. The map is the one that UCFS returned through [solve] with a graph and grammar.
     */
    @JvmStatic
    fun solve(pta: PTA): Map<VarNode, Set<AllocNode>> {
        val graph = PagExport.export(pta)
        return solve(graph, PointsToGrammar(graph.fields.size))
    }

    /**
     * Runs UCFS with [grammar] on [graph] from the start vertices `graph.allocVertices()` (the
     * objects) and returns, for each variable `v`, the objects `o` such that some path from `o` to
     * `v` spells a word of the start nonterminal of [grammar] (`UcfsSolver.reachablePairs` with
     * these start vertices).
     *
     * Only pairs (object, variable) go into the map: a pair whose second vertex is not a `VarNode`
     * (for example `(o, o)` when the grammar derives the empty word) is left out. With
     * [PointsToGrammar] this is the query of [solve] with a PTA; another grammar checks that the
     * export and the solver are not tied to L_FT (E3.md D10).
     *
     * @param graph the labeled graph, as made by [PagExport.export]
     * @param grammar a UCFS grammar over the labels of [PtLabels] with a start nonterminal
     * @return CI variable -> the objects that reach it; variables without objects have no key
     */
    @JvmStatic
    fun solve(graph: UcfsGraph, grammar: Grammar): Map<VarNode, Set<AllocNode>> {
        val pairs = UcfsSolver.reachablePairs(graph.edges, grammar, graph.allocVertices())
        val result = HashMap<VarNode, MutableSet<AllocNode>>()
        for (p in pairs) {
            val obj = graph.nodeOf(p.from)
            val variable = graph.nodeOf(p.to)
            if (obj is AllocNode && variable is VarNode) {
                result.getOrPut(variable) { HashSet() }.add(obj)
            }
        }
        return result
    }
}
