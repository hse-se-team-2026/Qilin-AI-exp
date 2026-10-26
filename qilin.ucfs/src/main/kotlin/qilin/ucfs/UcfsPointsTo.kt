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

    /** The phases of the last [solve] with a graph and grammar on each thread. */
    private val lastPhases = ThreadLocal<PhaseMarks>()

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
     * The call times its phases on a [PhaseMarks] made at its start, which [lastPhaseMarks] returns
     * afterwards on the same thread: the phases of the solver, `UcfsSolver.PHASES` (`rsm`,
     * `input` with the call of `graph.allocVertices()`, `parse`, `roots`), then `pairs`: the vertex
     * pairs to the map (object, variable), until the map is complete.
     *
     * @param graph the labeled graph, as made by [PagExport.export]
     * @param grammar a UCFS grammar over the labels of [PtLabels] with a start nonterminal
     * @return CI variable -> the objects that reach it; variables without objects have no key
     */
    @JvmStatic
    fun solve(graph: UcfsGraph, grammar: Grammar): Map<VarNode, Set<AllocNode>> {
        val marks = PhaseMarks()
        val pairs = UcfsSolver.reachablePairs(graph.edges, grammar, { graph.allocVertices() }, marks)
        val result = HashMap<VarNode, MutableSet<AllocNode>>()
        for (p in pairs) {
            val obj = graph.nodeOf(p.from)
            val variable = graph.nodeOf(p.to)
            if (obj is AllocNode && variable is VarNode) {
                result.getOrPut(variable) { HashSet() }.add(obj)
            }
        }
        marks.end("pairs")
        lastPhases.set(marks)
        return result
    }

    /**
     * [solve] with a graph and grammar (the same answer: this overload calls it) that also puts
     * the nanoseconds of its phases into [times], in this order of insertion: `rsm`, `input`,
     * `parse`, `roots`, `pairs` (see [solve]). The value of a phase replaces a value already in
     * [times]; it is not added to it.
     *
     * @param times the map that receives phase name -> nanoseconds
     */
    @JvmStatic
    fun solve(graph: UcfsGraph, grammar: Grammar, times: MutableMap<String, Long>): Map<VarNode, Set<AllocNode>> {
        val result = solve(graph, grammar)
        times.putAll(lastPhaseMarks().durations())
        return result
    }

    /**
     * The phase boundaries of the last [solve] with a graph and grammar that returned on the
     * current thread: [PhaseMarks.start] is read at the start of that call and [PhaseMarks.end] is
     * the end of its last phase, `pairs`.
     *
     * @throws IllegalStateException if no such call has returned on this thread
     */
    @JvmStatic
    fun lastPhaseMarks(): PhaseMarks = checkNotNull(lastPhases.get()) { "UcfsPointsTo.solve has not run on this thread" }
}
