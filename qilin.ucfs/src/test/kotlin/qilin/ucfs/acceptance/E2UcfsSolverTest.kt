package qilin.ucfs.acceptance

import org.junit.Assert.assertEquals
import org.junit.Test
import qilin.ucfs.LabeledEdge
import qilin.ucfs.UcfsSolver
import qilin.ucfs.VertexPair
import qilin.ucfs.grammar.AnBnGrammar

/**
 * E2-S3 acceptance check (docs/ai/tickets/E2-S3.md): the Kotlin module qilin.ucfs runs UCFS
 * through its own API. Grammar S -> a S? b (a^n b^n, n >= 1); every vertex that occurs in an
 * edge is a start vertex. The expected pairs are derived by hand in the comments.
 */
class E2UcfsSolverTest {

    private fun edges(vararg e: Triple<Int, String, Int>) = e.map { LabeledEdge(it.first, it.second, it.third) }

    private fun pairs(vararg p: Pair<Int, Int>) = p.map { VertexPair(it.first, it.second) }.toSet()

    @Test
    fun chainAABB() {
        // 0 -a-> 1 -a-> 2 -b-> 3 -b-> 4: "ab" on 1..3, "aabb" on 0..4
        val g = edges(Triple(0, "a", 1), Triple(1, "a", 2), Triple(2, "b", 3), Triple(3, "b", 4))
        assertEquals(pairs(0 to 4, 1 to 3), UcfsSolver.reachablePairs(g, AnBnGrammar("a", "b")))
    }

    @Test
    fun unbalancedChain() {
        // 0 -a-> 1 -a-> 2 -b-> 3: only "ab" on 1..3
        val g = edges(Triple(0, "a", 1), Triple(1, "a", 2), Triple(2, "b", 3))
        assertEquals(pairs(1 to 3), UcfsSolver.reachablePairs(g, AnBnGrammar("a", "b")))
    }

    @Test
    fun cycleTerminates() {
        // 0 -a-> 1 -a-> 0 -b-> 2: from 1 "ab" via 0; from 0 any a^k needs k b-edges, there is one
        val g = edges(Triple(0, "a", 1), Triple(1, "a", 0), Triple(0, "b", 2))
        assertEquals(pairs(1 to 2), UcfsSolver.reachablePairs(g, AnBnGrammar("a", "b")))
    }

    @Test
    fun foreignLabelsBreakPaths() {
        // "c" is not a terminal of the grammar: 0 -a-> 1 -c-> 2 -b-> 3 has no a^n b^n path
        val g = edges(Triple(0, "a", 1), Triple(1, "c", 2), Triple(2, "b", 3))
        assertEquals(emptySet<VertexPair>(), UcfsSolver.reachablePairs(g, AnBnGrammar("a", "b")))
    }

    @Test
    fun terminalNamesComeFromTheGrammar() {
        // the same shape with other terminal names and vertex ids that do not start at 0
        val g = edges(Triple(5, "open", 6), Triple(6, "open", 7), Triple(7, "close", 8), Triple(8, "close", 9))
        assertEquals(pairs(5 to 9, 6 to 8), UcfsSolver.reachablePairs(g, AnBnGrammar("open", "close")))
        assertEquals(emptySet<VertexPair>(), UcfsSolver.reachablePairs(g, AnBnGrammar("a", "b")))
    }

    @Test
    fun emptyGraph() {
        assertEquals(emptySet<VertexPair>(), UcfsSolver.reachablePairs(emptyList(), AnBnGrammar("a", "b")))
    }

    @Test
    fun repeatedQueriesGiveTheSameAnswer() {
        // a Gll instance answers only once (skill ucfs, gotcha 2): every call must run a fresh query
        val g = edges(Triple(0, "a", 1), Triple(1, "b", 2))
        val grammar = AnBnGrammar("a", "b")
        assertEquals(pairs(0 to 2), UcfsSolver.reachablePairs(g, grammar))
        assertEquals(pairs(0 to 2), UcfsSolver.reachablePairs(g, grammar))
    }
}
