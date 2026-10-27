package qilin.ucfs.idr

import org.cfl_idr_with_gll.getMROverApprox
import org.cfl_idr_with_gll.getOnDemandMR
import org.cfl_idr_with_gll.getUnderApprox
import org.cfl_idr_with_gll.models.Path
import org.cfl_idr_with_gll.terminal.DefaultTerminalFormat
import org.ucfs.input.InputGraph
import org.ucfs.input.TerminalInputLabel
import org.ucfs.rsm.symbol.Term
import qilin.ucfs.PhaseMarks
import java.util.function.BiConsumer

/**
 * The answer of cfl-idr-with-gll on an [IdrGraph] (vertex id pairs `(source, target)`, `source != target`).
 *
 * @property under the under-approximation (`getUnderApprox`: Dyck reachability over all bracket kinds
 *   together; each pair is reachable in the interleaved Dyck language)
 * @property over the over-approximation of mutual refinement with the grammar of the run (`getMROverApprox`)
 * @property onDemand the on-demand refinement (`getOnDemandMR`) for the grammars `parityD` and
 *   `on-demand`, `null` for the others
 * @property times milliseconds per phase, in the order of the phases: `input-ms` (building the input
 *   graph of the first phase), `under-ms`, `over-ms`, `ondemand-ms` (only with [onDemand]); the input
 *   graphs of `over` and `ondemand` are built inside those phases
 */
class IdrResult(
    val under: Set<Pair<Int, Int>>,
    val over: Set<Pair<Int, Int>>,
    val onDemand: Set<Pair<Int, Int>>?,
    val times: Map<String, Long>,
)

/** Runs cfl-idr-with-gll in the JVM of Qilin on an exported [IdrGraph] (E6-S3; E6.md D1, D2). */
object IdrSolve {

    /** Grammar keys of the CLI of cfl-idr (`Main.kt`, `SUPPORTED_GRAMMARS` without `parityK`). */
    @JvmField
    val GRAMMARS: List<String> = listOf("parity", "parity2", "se", "project", "exclude", "all", "parityD", "on-demand")

    /**
     * Solves [g] with [grammar] the way the CLI of cfl-idr does (`Main.kt:152-176` at the pin):
     * `under = getUnderApprox(graph)`, then `over = getMROverApprox(graph, grammar', 1, under)`, and for
     * `parityD` / `on-demand` also `onDemand = getOnDemandMR(graph, under, over, parityD)`, where
     * `parityD` runs the over-approximation with `parity` (and `parityD = true`) and `on-demand` with
     * `all` (and `parityD = false`). No value-flow pruning, terminal format `DefaultTerminalFormat`.
     *
     * Each of the calls gets a new `InputGraph` built from [IdrGraph.edges] (vertex = id, label =
     * `TerminalInputLabel(Term(label))`, as the CLI's `DotParser` reads the DOT file of
     * [IdrExport.writeDot]): cfl-idr adds start vertices to the graph it is given, so a graph is not
     * shared between calls.
     *
     * [onPhase], if given, is called on this thread with the key of [IdrResult.times] and the
     * milliseconds of a phase as soon as the phase ends, before the next one starts (so a caller
     * that prints it shows where a run stopped).
     *
     * @throws IllegalArgumentException if [grammar] is not one of [GRAMMARS]
     */
    @JvmStatic
    @JvmOverloads
    fun solve(g: IdrGraph, grammar: String, onPhase: BiConsumer<String, Long>? = null): IdrResult {
        require(grammar in GRAMMARS) { "unknown cfl-idr grammar '$grammar', expected one of $GRAMMARS" }
        val (overGrammar, onDemand, parityD) = when (grammar) {
            "parityD" -> Triple("parity", true, true)
            "on-demand" -> Triple("all", true, false)
            else -> Triple(grammar, false, false)
        }
        val times = LinkedHashMap<String, Long>()
        val marks = PhaseMarks()
        var prev = marks.start
        fun done(key: String) {
            val t = marks.end(key)
            val ms = (t - prev) / 1_000_000
            prev = t
            times[key] = ms
            onPhase?.accept(key, ms)
        }

        val underInput = inputGraph(g)
        done("input-ms")
        val under = getUnderApprox(underInput, false, DefaultTerminalFormat)
        done("under-ms")
        val over = getMROverApprox(inputGraph(g), overGrammar, 1, under, false, DefaultTerminalFormat)
        done("over-ms")
        var refined: Set<Path<Int>>? = null
        if (onDemand) {
            refined = getOnDemandMR(inputGraph(g), under, over, parityD, false, DefaultTerminalFormat)
            done("ondemand-ms")
        }
        return IdrResult(pairs(under), pairs(over), refined?.let { pairs(it) }, times)
    }

    private fun inputGraph(g: IdrGraph): InputGraph<Int, TerminalInputLabel> {
        val ig = InputGraph<Int, TerminalInputLabel>()
        for (e in g.edges) {
            ig.addVertex(e.from)
            ig.addVertex(e.to)
            ig.addEdge(e.from, TerminalInputLabel(Term(e.label)), e.to)
        }
        return ig
    }

    private fun pairs(paths: Set<Path<Int>>): Set<Pair<Int, Int>> = paths.mapTo(HashSet(paths.size * 2)) { it.source to it.target }
}
