package qilin.ucfs.acceptance

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import qilin.ucfs.LabeledEdge
import qilin.ucfs.PtLabels
import qilin.ucfs.UcfsSolver
import qilin.ucfs.VertexPair
import qilin.ucfs.grammar.AnBnGrammar
import qilin.ucfs.grammar.PointsToGrammar

/**
 * E5-S1 acceptance check (docs/ai/tickets/E5-S1.md): the solver call with phase times,
 * `UcfsSolver.reachablePairs(edges, grammar, startVertices, times)`, answers as the call without
 * them and puts the nanoseconds of its phases into `times`: "rsm" (building the RSM of the grammar),
 * "input" (the input graph), "parse" (GLL), "roots" (parse roots to vertex pairs), in this order.
 *
 * The RSM of `PointsToGrammar(k)` is built lazily (`Grammar.rsm`); its build time grows fast with k
 * (planner: k = 676 about 0.18 s, k = 2000 about 0.66 s, k = 4000 about 3.1 s), while GLL on a graph of
 * two edges takes well under a millisecond once warm. So with a fresh grammar of many fields the phase
 * "rsm" must hold the build (much longer than "parse"), and with the same grammar instance again the
 * build is not repeated.
 */
class E5PhaseTimesTest {

    private val phases = listOf("rsm", "input", "parse", "roots")

    private fun edges(vararg e: Triple<Int, String, Int>) = e.map { LabeledEdge(it.first, it.second, it.third) }

    /** x1 = new o0; y4 = new o3; x1.f0 = y4 (store y4 -> x1); z2 = x1.f0 (load x1 -> z2); w5 = z2; plus the _bar edges. */
    private fun pointsToGraph(): List<LabeledEdge> {
        val fwd = edges(
            Triple(0, PtLabels.NEW, 1), Triple(3, PtLabels.NEW, 4),
            Triple(4, PtLabels.store(0), 1), Triple(1, PtLabels.load(0), 2), Triple(2, PtLabels.ASSIGN, 5),
        )
        return fwd + fwd.map { LabeledEdge(it.to, PtLabels.bar(it.label), it.from) }
    }

    private fun timed(edges: List<LabeledEdge>, grammar: PointsToGrammar, starts: List<Int>): Map<String, Long> {
        val times = LinkedHashMap<String, Long>()
        UcfsSolver.reachablePairs(edges, grammar, starts, times)
        return times
    }

    @Test
    fun timedCallAnswersAsUntimed() {
        val anbn = edges(Triple(0, "a", 1), Triple(1, "a", 2), Triple(2, "b", 3), Triple(3, "b", 4))
        for (starts in listOf(listOf(0), listOf(0, 1), listOf(0, 1, 2, 3, 4), emptyList())) {
            val times = LinkedHashMap<String, Long>()
            val timedPairs = UcfsSolver.reachablePairs(anbn, AnBnGrammar("a", "b"), starts, times)
            assertEquals("a^n b^n from $starts", UcfsSolver.reachablePairs(anbn, AnBnGrammar("a", "b"), starts), timedPairs)
            assertEquals(phases, times.keys.toList())
            assertTrue("times >= 0: $times", times.values.all { it >= 0 })
        }
        val g = pointsToGraph()
        for (starts in listOf(listOf(0, 3), listOf(3), (0..5).toList())) {
            val times = LinkedHashMap<String, Long>()
            val timedPairs = UcfsSolver.reachablePairs(g, PointsToGrammar(1), starts, times)
            assertEquals("flowsTo from $starts", UcfsSolver.reachablePairs(g, PointsToGrammar(1), starts), timedPairs)
            assertEquals(phases, times.keys.toList())
            assertTrue("times >= 0: $times", times.values.all { it >= 0 })
        }
        // derived by hand: o0 reaches x1; o3 reaches y4, is stored into x1.f0 and loaded into z2, then w5
        val pairs = UcfsSolver.reachablePairs(g, PointsToGrammar(1), listOf(0, 3), LinkedHashMap())
        assertEquals(
            setOf(VertexPair(0, 1), VertexPair(3, 4), VertexPair(3, 2), VertexPair(3, 5)),
            pairs.filter { it.from != it.to }.toSet(),
        )
    }

    @Test
    fun rsmPhaseHoldsTheRsmBuild() {
        val g = pointsToGraph()
        // warm up the classes of the solver on another grammar instance
        repeat(3) { timed(g, PointsToGrammar(1), listOf(0, 3)) }
        val grammar = PointsToGrammar(1500)
        val first = timed(g, grammar, listOf(0, 3))
        val second = timed(g, grammar, listOf(0, 3))
        val rsm1 = first.getValue("rsm")
        val parse1 = first.getValue("parse")
        val rsm2 = second.getValue("rsm")
        assertTrue("fresh PointsToGrammar(1500): rsm $rsm1 ns >= 20 x parse $parse1 ns ($first)", rsm1 >= 20 * parse1)
        assertTrue("same grammar again: rsm $rsm2 ns <= rsm of the first call $rsm1 ns / 20 ($second)", 20 * rsm2 <= rsm1)
        assertEquals(phases, second.keys.toList())
    }
}
