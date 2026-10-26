package qilin.ucfs

import org.ucfs.grammar.combinator.Grammar
import org.ucfs.input.InputGraph
import org.ucfs.input.TerminalInputLabel
import org.ucfs.parser.Gll
import org.ucfs.rsm.symbol.Term
import org.ucfs.sppf.node.RangeSppfNode

/**
 * A directed graph edge `from -label-> to`.
 *
 * The label is matched against the grammar terminals as `Term(label)`, so a grammar that
 * should accept this edge must use the terminal `Term(label)` with the same string.
 */
data class LabeledEdge(val from: Int, val label: String, val to: Int)

/** A pair of vertices `(from, to)` connected by a path whose labels form a word of the grammar. */
data class VertexPair(val from: Int, val to: Int)

/** Runs the UCFS solver (GLL over the grammar RSM) on graphs given as lists of labeled edges. */
object UcfsSolver {

    /**
     * Returns all pairs `(u, v)` such that some path from `u` to `v` in [edges] spells a word
     * derived from the start nonterminal of [grammar] (CFL-reachability).
     *
     * Start vertices: every vertex that occurs in [edges], as a source or as a target, is a
     * start vertex, so the answer covers all sources. Vertices without edges do not exist for
     * the solver. An edge label `l` becomes `TerminalInputLabel(Term(l))`; labels that are not
     * terminals of [grammar] never match and only break paths.
     *
     * Each call builds a new input graph and runs a fresh `Gll` instance: a `Gll` answers
     * `parse()` only once (a second call returns nothing), so instances are never reused.
     * The grammar RSM is built once per [grammar] instance and is reused across calls.
     *
     * @param edges the labeled edges of the input graph; may be empty
     * @param grammar the UCFS grammar with a start nonterminal (`asStart()`)
     * @return the reachable pairs; empty for an empty graph
     */
    @JvmStatic
    fun reachablePairs(edges: Collection<LabeledEdge>, grammar: Grammar): Set<VertexPair> {
        val graph = InputGraph<Int, TerminalInputLabel>()
        for (e in edges) {
            graph.addStartVertex(e.from)
            graph.addStartVertex(e.to)
            graph.addEdge(e.from, TerminalInputLabel(Term(e.label)), e.to)
        }
        val roots = Gll.gll(grammar.rsm, graph).parse()
        return roots.mapTo(HashSet()) { root ->
            val range = checkNotNull(root.inputRange) { "UCFS returned a parse root without an input range" }
            VertexPair(range.from, range.to)
        }
    }

    /**
     * Returns the pairs `(u, v)` with `u` in [startVertices] such that some path from `u` to `v`
     * in [edges] spells a word derived from the start nonterminal of [grammar].
     *
     * This is the answer of the two-argument [reachablePairs] restricted to `u` in
     * [startVertices], computed by starting GLL from these vertices only (they are the
     * `addStartVertex` set of the input graph), not by filtering the all-pairs answer. A pair
     * `(v, v)` for the empty word is reported for a start vertex `v` when the start nonterminal of
     * [grammar] derives the empty word, also when `v` has no edges, and is not reported for other
     * vertices. Paths may pass through and end at any vertex of [edges]. An empty
     * [startVertices] gives an empty answer. Labels are matched as in the two-argument
     * [reachablePairs].
     *
     * Each call builds a new input graph and runs one fresh `Gll` instance; the grammar RSM is
     * built once per [grammar] instance and is reused across calls. The call runs the code of the
     * timed overloads (the phases are timed and dropped).
     *
     * @param edges the labeled edges of the input graph; may be empty
     * @param grammar the UCFS grammar with a start nonterminal (`asStart()`)
     * @param startVertices the vertices that paths start from; duplicates are ignored
     * @return the reachable pairs whose first vertex is in [startVertices]
     */
    @JvmStatic
    fun reachablePairs(
        edges: Collection<LabeledEdge>,
        grammar: Grammar,
        startVertices: Collection<Int>,
    ): Set<VertexPair> = reachablePairs(edges, grammar, { startVertices }, PhaseMarks())

    /**
     * The three-argument [reachablePairs] (the same answer, by the same code) that also puts the
     * nanoseconds of its phases into [times], in this order of insertion: [PHASES] = `rsm`,
     * `input`, `parse`, `roots` (see [reachablePairs] with [PhaseMarks] for what each phase holds).
     * The value of a phase is set once per call and replaces a value already in [times]; it is not
     * added to it. The phases are adjacent: together they span the call from the creation of its
     * [PhaseMarks], its first statement, to the end of `roots`.
     *
     * @param times the map that receives phase name -> nanoseconds (`System.nanoTime` differences)
     */
    @JvmStatic
    fun reachablePairs(
        edges: Collection<LabeledEdge>,
        grammar: Grammar,
        startVertices: Collection<Int>,
        times: MutableMap<String, Long>,
    ): Set<VertexPair> {
        val marks = PhaseMarks()
        val pairs = reachablePairs(edges, grammar, { startVertices }, marks)
        times.putAll(marks.durations())
        return pairs
    }

    /** The phases of a solver call, in the order they run. */
    @JvmField
    val PHASES: List<String> = listOf("rsm", "input", "parse", "roots")

    /**
     * The three-argument [reachablePairs] that ends the phases [PHASES] on [marks]; the
     * three- and four-argument overloads and `UcfsPointsTo.solve` run this code. Each phase starts
     * where the previous one ended (the first one at the last boundary of [marks] when it is
     * called, its start for a fresh [marks]) and ends with one `System.nanoTime` read:
     * - `rsm`: `grammar.rsm`, the RSM of [grammar]. It is built lazily on the first access to a
     *   [grammar] instance, so this phase holds the build for a fresh instance and next to nothing
     *   for one already used; it is read here, before `Gll.gll`, so that the build is not counted
     *   in `parse`;
     * - `input`: the input graph (vertices and labeled edges of [edges]) and its start vertices,
     *   including the call of [startVertices];
     * - `parse`: `Gll.gll(rsm, graph).parse()`, the GLL run that returns the SPPF roots;
     * - `roots`: the roots to the set of [VertexPair] (the input range of each root).
     *
     * @param startVertices called once, in the phase `input`, for the vertices that paths start from
     * @param marks the clock that receives the ends of the phases; a phase that it already holds
     *   is rejected ([PhaseMarks.end])
     */
    @JvmStatic
    fun reachablePairs(
        edges: Collection<LabeledEdge>,
        grammar: Grammar,
        startVertices: () -> Collection<Int>,
        marks: PhaseMarks,
    ): Set<VertexPair> {
        val rsm = grammar.rsm
        marks.end("rsm")
        val graph = inputGraph(edges, startVertices())
        marks.end("input")
        val roots = Gll.gll(rsm, graph).parse()
        marks.end("parse")
        val pairs = vertexPairs(roots)
        marks.end("roots")
        return pairs
    }

    /** The input graph of [edges] whose start vertices are [startVertices]; every vertex of [edges] is in it. */
    private fun inputGraph(edges: Collection<LabeledEdge>, startVertices: Collection<Int>): InputGraph<Int, TerminalInputLabel> {
        val graph = InputGraph<Int, TerminalInputLabel>()
        for (e in edges) {
            graph.addVertex(e.from)
            graph.addVertex(e.to)
            graph.addEdge(e.from, TerminalInputLabel(Term(e.label)), e.to)
        }
        for (v in startVertices) graph.addStartVertex(v)
        return graph
    }

    /** The pairs (start, end) of the input ranges of the parse roots [roots]. */
    private fun vertexPairs(roots: Set<RangeSppfNode<Int>>): Set<VertexPair> =
        roots.mapTo(HashSet()) { root ->
            val range = checkNotNull(root.inputRange) { "UCFS returned a parse root without an input range" }
            VertexPair(range.from, range.to)
        }
}
