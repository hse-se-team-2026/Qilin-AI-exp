package qilin.ucfs.acceptance

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.ucfs.grammar.combinator.Grammar
import org.ucfs.grammar.combinator.regexp.Epsilon
import org.ucfs.grammar.combinator.regexp.Nt
import org.ucfs.grammar.combinator.regexp.Option
import org.ucfs.grammar.combinator.regexp.Regexp
import org.ucfs.grammar.combinator.regexp.many
import org.ucfs.grammar.combinator.regexp.or
import org.ucfs.grammar.combinator.regexp.times
import org.ucfs.rsm.symbol.Term
import qilin.ucfs.LabeledEdge
import qilin.ucfs.PtLabels
import qilin.ucfs.UcfsSolver
import qilin.ucfs.VertexPair
import qilin.ucfs.grammar.AnBnGrammar
import qilin.ucfs.grammar.PointsToGrammar
import kotlin.random.Random

/**
 * E3-S2 acceptance check (docs/ai/tickets/E3-S2.md).
 *
 * 1. PointsToGrammar(k) (flowsTo of Sridharan et al. 2005, Fig. 3, fields 0 until k, labels of
 *    PtLabels) gives on UCFS exactly the pairs of an independent reference: a textbook worklist
 *    CFL-reachability solver (Melski & Reps 2000; Hellings 2014) over a normalized grammar written
 *    here by hand from Fig. 3. Random graphs with fixed seeds and hand-made cases.
 * 2. The same engine (UcfsSolver, unchanged code path) on nine more grammars of different kinds,
 *    against the same reference: a^n b^n (AnBnGrammar), Dyck-2 with epsilon, the ambiguous
 *    left-recursive S -> S S | a, the regular new assign* (points-to without fields), hidden left
 *    recursion S -> A S b | c with A -> eps | a, a cycle of unit rules S -> T | a, T -> S | b, the
 *    infinitely ambiguous S -> S S | a | eps, nested stars S -> (a*)* b and right recursion
 *    S -> a S | b (the last five were proposed by critic-E3, E3.md m3). Every grammar needs >= 30
 *    random graphs with a pair (u, v), u != v, in the reference answer (an epsilon pair (v, v)
 *    alone does not count, E3.md m2). This is the oracle part of "why UCFS works on different
 *    grammars" (E3.md D10, E3-S5).
 * 3. reachablePairs(edges, grammar, startVertices) = the all-pairs answer restricted to paths that
 *    start in startVertices (also for the epsilon pairs (v, v)).
 * 4. PointsToGrammar with many fields builds and answers, and keeps the fields apart: different
 *    objects stored in different fields of one base are not mixed (E3.md m1).
 * 5. A second reading of points-to by other authors: the PointsTo nonterminal of the grammar of the
 *    UCFS team (.ucfs/src cfpq-paths-app/src/main/kotlin/org/ucfs/paths/Main.kt:18-35, fields 0..3,
 *    edges from a variable to its object), generalized here to k fields, on the same graph with the
 *    labels renamed gives exactly the reversed pairs of PointsToGrammar (E3.md M6).
 */
class E3GrammarTest {

    // ---------------------------------------------------------------- reference CFL-R solver
    /** Normalized grammar: A -> eps, A -> t, A -> B, A -> B C. */
    private class Norm(val start: String) {
        val eps = HashSet<String>()
        val term = ArrayList<Pair<String, String>>()
        val unit = ArrayList<Pair<String, String>>()
        val bin = ArrayList<Triple<String, String, String>>()
        fun eps(a: String) = apply { eps.add(a) }
        fun t(a: String, t: String) = apply { term.add(a to t) }
        fun u(a: String, b: String) = apply { unit.add(a to b) }
        fun b(a: String, b: String, c: String) = apply { bin.add(Triple(a, b, c)) }
    }

    /** All (u, v) with a path u -> v whose word derives from norm.start (worklist, cubic). */
    private fun reference(norm: Norm, edges: Collection<LabeledEdge>, extraVertices: Collection<Int>): Set<VertexPair> {
        data class F(val nt: String, val from: Int, val to: Int)
        val facts = HashSet<F>()
        val work = ArrayDeque<F>()
        val byFrom = HashMap<Pair<String, Int>, MutableSet<Int>>()
        val byTo = HashMap<Pair<String, Int>, MutableSet<Int>>()
        fun add(f: F) {
            if (facts.add(f)) {
                byFrom.getOrPut(f.nt to f.from) { HashSet() }.add(f.to)
                byTo.getOrPut(f.nt to f.to) { HashSet() }.add(f.from)
                work.add(f)
            }
        }
        val vertices = HashSet<Int>(extraVertices)
        edges.forEach { vertices.add(it.from); vertices.add(it.to) }
        for (a in norm.eps) vertices.forEach { add(F(a, it, it)) }
        for (e in edges) for ((a, t) in norm.term) if (t == e.label) add(F(a, e.from, e.to))
        while (work.isNotEmpty()) {
            val f = work.removeFirst()
            for ((a, b) in norm.unit) if (b == f.nt) add(F(a, f.from, f.to))
            for ((a, b, c) in norm.bin) {
                if (b == f.nt) for (w in byFrom[c to f.to].orEmpty().toList()) add(F(a, f.from, w))
                if (c == f.nt) for (w in byTo[b to f.from].orEmpty().toList()) add(F(a, w, f.to))
            }
        }
        return facts.filter { it.nt == norm.start }.mapTo(HashSet()) { VertexPair(it.from, it.to) }
    }

    /** Fig. 3 of Sridharan et al. 2005, normalized by hand; labels as PtLabels. */
    private fun flowsToNorm(k: Int): Norm {
        val n = Norm("FT")
        fun bar(l: String) = PtLabels.bar(l)
        n.t("FT", PtLabels.NEW)                          // flowsTo -> new
        n.t("ASG", PtLabels.ASSIGN).b("FT", "FT", "ASG")  // flowsTo -> flowsTo assign
        n.t("FTB", bar(PtLabels.NEW))                    // flowsTo~ -> new~
        n.t("ASGB", bar(PtLabels.ASSIGN)).b("FTB", "ASGB", "FTB") // flowsTo~ -> assign~ flowsTo~
        n.b("AL", "FTB", "FT")                           // alias -> flowsTo~ flowsTo
        for (i in 0 until k) {
            // flowsTo -> flowsTo store[i] alias load[i]
            n.t("ST$i", PtLabels.store(i)).t("LD$i", PtLabels.load(i))
            n.b("SA$i", "ST$i", "AL").b("SAL$i", "SA$i", "LD$i").b("FT", "FT", "SAL$i")
            // flowsTo~ -> load[i]~ alias store[i]~ flowsTo~
            n.t("LDB$i", bar(PtLabels.load(i))).t("STB$i", bar(PtLabels.store(i)))
            n.b("LA$i", "LDB$i", "AL").b("LAS$i", "LA$i", "STB$i").b("FTB", "LAS$i", "FTB")
        }
        return n
    }

    // ------------------------------------------------------- grammars defined only in this test
    /** Dyck language over two bracket kinds, with epsilon: S -> eps | ( S ) S | [ S ] S. */
    class Dyck2 : Grammar() {
        val S by Nt().asStart()
        init {
            S /= Option((Term("(") * S * Term(")") * S) or (Term("[") * S * Term("]") * S))
        }
    }

    /** Ambiguous and left-recursive: S -> S S | a. */
    class AmbiguousConcat : Grammar() {
        val S by Nt().asStart()
        init {
            S /= (S * S) or Term("a")
        }
    }

    /** Points-to without fields (regular): flowsTo -> new assign*. */
    class FlowsToNoFields : Grammar() {
        val S by Nt().asStart()
        init {
            S /= Term(PtLabels.NEW) * many(Term(PtLabels.ASSIGN))
        }
    }

    /** Hidden left recursion: S -> A S b | c, A -> eps | a. */
    class HiddenLeftRec : Grammar() {
        val S by Nt().asStart()
        val A by Nt()
        init {
            A /= Option(Term("a"))
            S /= (A * S * Term("b")) or Term("c")
        }
    }

    /** Cycle of unit rules: S -> T | a, T -> S | b. */
    class UnitCycle : Grammar() {
        val S by Nt().asStart()
        val T by Nt()
        init {
            S /= T or Term("a")
            T /= S or Term("b")
        }
    }

    /** Infinitely ambiguous with epsilon: S -> S S | a | eps. */
    class EpsAmbiguous : Grammar() {
        val S by Nt().asStart()
        init {
            S /= (S * S) or Term("a") or Epsilon
        }
    }

    /** Nested stars: S -> (a*)* b. */
    class NestedStar : Grammar() {
        val S by Nt().asStart()
        init {
            S /= many(many(Term("a"))) * Term("b")
        }
    }

    /** Right recursion: S -> a S | b. */
    class RightRec : Grammar() {
        val S by Nt().asStart()
        init {
            S /= (Term("a") * S) or Term("b")
        }
    }

    /**
     * The points-to grammar of the UCFS team (cfpq-paths-app Main.kt:18-35 at the UCFS pin): edges
     * point from a variable to what it reads, "x -alloc-> o" for x = new o, "x -assign-> y" for
     * x = y, "z -load_i-> x" for z = x.f, "x -store_i-> y" for x.f = y, and "_r" marks the reversed
     * edge. PointsTo(x, o): x points to o. Here: fields 0 until k instead of 0..3, start PointsTo
     * (the original start S asks a different question).
     */
    class UcfsTeamPointsTo(k: Int) : Grammar() {
        val PointsTo by Nt().asStart()
        val FlowsTo by Nt()
        val Alias by Nt()
        init {
            var back: Regexp = Term("assign")
            var fwd: Regexp = Term("assign_r")
            for (i in 0 until k) {
                back = back or (Term("load_$i") * Alias * Term("store_$i"))
                fwd = fwd or (Term("store_${i}_r") * Alias * Term("load_${i}_r"))
            }
            PointsTo /= many(back) * Term("alloc")
            FlowsTo /= Term("alloc_r") * many(fwd)
            Alias /= PointsTo * FlowsTo
        }
    }

    /**
     * Our edge labels renamed to the labels of [UcfsTeamPointsTo], the graph unchanged: our forward
     * edge u -l-> v (e.g. o -new-> x) is their reversed edge ("alloc_r", ...), our reversed edge
     * v -l_bar-> u is their edge v -> u ("alloc", ...); store/load keep their field index.
     */
    private fun teamLabel(l: String): String {
        val bar = l.endsWith(PtLabels.BAR_SUFFIX)
        val base = if (bar) l.removeSuffix(PtLabels.BAR_SUFFIX) else l
        val name = if (base == PtLabels.NEW) "alloc" else base
        return if (bar) name else name + "_r"
    }

    private val hiddenNorm = Norm("S").t("S", "c").eps("A").t("A", "a").t("B", "b").b("X", "S", "B").b("S", "A", "X")
    private val unitNorm = Norm("S").t("S", "a").t("T", "b").u("S", "T").u("T", "S")
    private val epsAmbNorm = Norm("S").eps("S").t("S", "a").b("S", "S", "S")
    private val nestedNorm = Norm("S").eps("X").t("A", "a").b("X", "X", "A").t("B", "b").b("S", "X", "B")
    private val rightNorm = Norm("S").t("S", "b").t("A", "a").b("S", "A", "S")

    private val anbnNorm = Norm("S").t("A", "a").t("B", "b").b("S", "A", "B").b("X", "S", "B").b("S", "A", "X")
    private val dyckNorm = Norm("S").eps("S")
        .t("L1", "(").t("R1", ")").t("L2", "[").t("R2", "]")
        .b("X1", "S", "R1").b("Y1", "X1", "S").b("S", "L1", "Y1")
        .b("X2", "S", "R2").b("Y2", "X2", "S").b("S", "L2", "Y2")
    private val ambNorm = Norm("S").t("S", "a").b("S", "S", "S")
    private val noFieldsNorm = Norm("S").t("S", PtLabels.NEW).t("A", PtLabels.ASSIGN).b("S", "S", "A")

    // ------------------------------------------------------------------------ graph helpers
    private fun randomGraph(rnd: Random, alphabet: List<String>, maxV: Int): List<LabeledEdge> {
        val n = rnd.nextInt(2, maxV + 1)
        val m = rnd.nextInt(1, 3 * n + 1)
        return List(m) { LabeledEdge(rnd.nextInt(n), alphabet[rnd.nextInt(alphabet.size)], rnd.nextInt(n)) }.distinct()
    }

    /** Forward points-to edges plus their reversed "_bar" edges, as PagExport produces them. */
    private fun withBars(fwd: List<LabeledEdge>): List<LabeledEdge> =
        (fwd + fwd.map { LabeledEdge(it.to, PtLabels.bar(it.label), it.from) }).distinct()

    private fun fwdAlphabet(k: Int) = listOf(PtLabels.NEW, PtLabels.ASSIGN) +
        (0 until k).flatMap { listOf(PtLabels.store(it), PtLabels.load(it)) }

    private fun newSources(edges: List<LabeledEdge>) = edges.filter { it.label == PtLabels.NEW }.map { it.from }.toSet()

    private fun checkPointsTo(edges: List<LabeledEdge>, k: Int, what: String) {
        val starts = newSources(edges)
        val expected = reference(flowsToNorm(k), edges, emptyList()).filterTo(HashSet()) { it.from in starts }
        val actual = UcfsSolver.reachablePairs(edges, PointsToGrammar(k), starts)
        assertEquals("PointsToGrammar($k) on $what: $edges", expected, actual)
    }

    private fun e(from: Int, label: String, to: Int) = LabeledEdge(from, label, to)

    // ------------------------------------------------------------------------------- tests
    /** Hand case (derived by hand): x.f = new; b = c-aliased; z = c.f. */
    @Test
    fun pointsToHandCases() {
        // 0 = o, 1 = x, 2 = o2, 3 = b, 4 = c, 5 = z ; x = new o; b = new o2; b.f = x; c = b; z = c.f
        val g = withBars(listOf(e(0, PtLabels.NEW, 1), e(2, PtLabels.NEW, 3), e(1, PtLabels.store(0), 3),
            e(3, PtLabels.ASSIGN, 4), e(4, PtLabels.load(0), 5)))
        val expected = setOf(VertexPair(0, 1), VertexPair(0, 5), VertexPair(2, 3), VertexPair(2, 4))
        assertEquals(expected, UcfsSolver.reachablePairs(g, PointsToGrammar(1), listOf(0, 2)))
        // same program but the load reads field 1: o does not reach z
        val g2 = withBars(listOf(e(0, PtLabels.NEW, 1), e(2, PtLabels.NEW, 3), e(1, PtLabels.store(0), 3),
            e(3, PtLabels.ASSIGN, 4), e(4, PtLabels.load(1), 5)))
        assertEquals(setOf(VertexPair(0, 1), VertexPair(2, 3), VertexPair(2, 4)),
            UcfsSolver.reachablePairs(g2, PointsToGrammar(2), listOf(0, 2)))
        // the base of the load is not an alias of the base of the store: no flow
        val g3 = withBars(listOf(e(0, PtLabels.NEW, 1), e(2, PtLabels.NEW, 3), e(6, PtLabels.NEW, 4),
            e(1, PtLabels.store(0), 3), e(4, PtLabels.load(0), 5)))
        assertEquals(setOf(VertexPair(0, 1), VertexPair(2, 3), VertexPair(6, 4)),
            UcfsSolver.reachablePairs(g3, PointsToGrammar(1), listOf(0, 2, 6)))
        // list cycle: x = new o; x.next = y; y = new o2; x = x.next  ->  o2 reaches x as well
        val g4 = withBars(listOf(e(0, PtLabels.NEW, 1), e(2, PtLabels.NEW, 3), e(3, PtLabels.store(0), 1),
            e(1, PtLabels.load(0), 1)))
        assertEquals(setOf(VertexPair(0, 1), VertexPair(2, 3), VertexPair(2, 1)),
            UcfsSolver.reachablePairs(g4, PointsToGrammar(1), listOf(0, 2)))
    }

    @Test
    fun pointsToRandomGraphsWithBars() {
        for (seed in 0 until 150) {
            val rnd = Random(20261018 + seed)
            val k = 1 + seed % 3
            checkPointsTo(withBars(randomGraph(rnd, fwdAlphabet(k), 10)), k, "seed $seed (bars)")
        }
    }

    @Test
    fun pointsToRandomGraphsAnyLabels() {
        // labels drawn independently, including unmatched _bar edges and labels outside the grammar
        for (seed in 0 until 150) {
            val rnd = Random(7_000_000 + seed)
            val k = 1 + seed % 3
            val alphabet = fwdAlphabet(k).flatMap { listOf(it, PtLabels.bar(it)) } + "other"
            checkPointsTo(randomGraph(rnd, alphabet, 9), k, "seed $seed (any labels)")
        }
    }

    private fun checkGrammar(name: String, grammar: Grammar, norm: Norm, alphabet: List<String>, seedBase: Int) {
        var nonTrivial = 0
        for (seed in 0 until 120) {
            val rnd = Random(seedBase + seed)
            val g = randomGraph(rnd, alphabet, 9)
            val expected = reference(norm, g, emptyList())
            val actual = UcfsSolver.reachablePairs(g, grammar)
            assertEquals("$name, seed $seed: $g", expected, actual)
            if (expected.any { it.from != it.to }) nonTrivial++
        }
        println("E3GrammarTest $name: 120 random graphs equal to the reference, $nonTrivial with a pair (u, v), u != v")
        assertTrue("$name: the random graphs must exercise the grammar ($nonTrivial < 30)", nonTrivial >= 30)
    }

    @Test
    fun otherGrammarsAgainstReference() {
        checkGrammar("AnBn", AnBnGrammar("a", "b"), anbnNorm, listOf("a", "b", "c"), 100)
        checkGrammar("Dyck2", Dyck2(), dyckNorm, listOf("(", ")", "[", "]"), 200)
        checkGrammar("S->SS|a", AmbiguousConcat(), ambNorm, listOf("a", "b"), 300)
        checkGrammar("new assign*", FlowsToNoFields(), noFieldsNorm, listOf(PtLabels.NEW, PtLabels.ASSIGN, "x"), 400)
        checkGrammar("S->A S b|c, A->eps|a", HiddenLeftRec(), hiddenNorm, listOf("a", "b", "c"), 9100)
        checkGrammar("S->T|a, T->S|b", UnitCycle(), unitNorm, listOf("a", "b", "c"), 9200)
        checkGrammar("S->S S|a|eps", EpsAmbiguous(), epsAmbNorm, listOf("a", "b", "c"), 9300)
        checkGrammar("S->(a*)* b", NestedStar(), nestedNorm, listOf("a", "b", "c"), 9400)
        checkGrammar("S->a S|b", RightRec(), rightNorm, listOf("a", "b", "c"), 9500)
    }

    @Test
    fun ucfsTeamGrammarGivesReversedPairs() {
        var nonTrivial = 0
        for (seed in 0 until 150) {
            val rnd = Random(30_000 + seed)
            val k = 1 + seed % 4
            val g = withBars(randomGraph(rnd, fwdAlphabet(k), 10))
            val objects = newSources(g)
            val ours = UcfsSolver.reachablePairs(g, PointsToGrammar(k), objects)
            val reference = reference(flowsToNorm(k), g, emptyList()).filterTo(HashSet()) { it.from in objects }
            assertEquals("seed $seed: PointsToGrammar = reference", reference, ours)
            val renamed = g.map { LabeledEdge(it.from, teamLabel(it.label), it.to) }
            val variables = g.flatMap { listOf(it.from, it.to) }.toSet()
            val theirs = UcfsSolver.reachablePairs(renamed, UcfsTeamPointsTo(k), variables)
                .filterTo(HashSet()) { it.to in objects }.mapTo(HashSet()) { VertexPair(it.to, it.from) }
            assertEquals("seed $seed (k=$k): UCFS team PointsTo reversed = PointsToGrammar: $g", ours, theirs)
            if (ours.isNotEmpty()) nonTrivial++
        }
        println("E3GrammarTest ucfsTeamPointsTo: 150 random graphs, reversed pairs = PointsToGrammar, $nonTrivial non-empty")
        assertTrue("random graphs must have points-to pairs ($nonTrivial < 50)", nonTrivial >= 50)
    }

    @Test
    fun explicitStartVertices() {
        for (seed in 0 until 60) {
            val rnd = Random(500 + seed)
            val g = randomGraph(rnd, listOf("(", ")", "[", "]"), 8)
            val vs = g.flatMap { listOf(it.from, it.to) }.toSet()
            val starts = vs.filter { rnd.nextBoolean() }.toSet()
            val all = UcfsSolver.reachablePairs(g, Dyck2())
            assertEquals("seed $seed: starts $starts on $g", all.filterTo(HashSet()) { it.from in starts },
                UcfsSolver.reachablePairs(g, Dyck2(), starts))
        }
        // epsilon pairs exist exactly for the start vertices
        val chain = listOf(e(0, "(", 1), e(1, ")", 2))
        assertEquals(setOf(VertexPair(1, 1)), UcfsSolver.reachablePairs(chain, Dyck2(), listOf(1)))
        assertEquals(setOf(VertexPair(0, 0), VertexPair(0, 2)), UcfsSolver.reachablePairs(chain, Dyck2(), listOf(0)))
    }

    @Test(timeout = 120_000)
    fun manyFields() {
        val k = 2000
        val t0 = System.nanoTime()
        val grammar = PointsToGrammar(k)
        grammar.rsm
        val t1 = System.nanoTime()
        // o (0) -new-> x_0 (2); ob (1) -new-> b (3); x_i -store_i-> b -load_i-> x_{i+1}: o reaches every x_i
        val fwd = ArrayList<LabeledEdge>()
        fwd.add(e(0, PtLabels.NEW, 2))
        fwd.add(e(1, PtLabels.NEW, 3))
        for (i in 0 until k) {
            fwd.add(e(2 + 2 * i, PtLabels.store(i), 3))
            fwd.add(e(3, PtLabels.load(i), 4 + 2 * i))
        }
        // fields kept apart: base c (object oc), objects q_j stored into field 97 * j of c and read
        // back from the same field into z_j; q_j reaches z_j and no other z
        val m = 20
        val c = 4 + 2 * k
        val oc = c + 1
        fwd.add(e(oc, PtLabels.NEW, c))
        val starts = arrayListOf(0, 1, oc)
        val expected = HashSet<VertexPair>()
        expected.add(VertexPair(1, 3))
        expected.add(VertexPair(oc, c))
        for (i in 0..k) expected.add(VertexPair(0, 2 + 2 * i))
        for (j in 0 until m) {
            val q = oc + 1 + 3 * j
            val y = q + 1
            val z = q + 2
            val fieldJ = 97 * j
            fwd.add(e(q, PtLabels.NEW, y))
            fwd.add(e(y, PtLabels.store(fieldJ), c))
            fwd.add(e(c, PtLabels.load(fieldJ), z))
            starts.add(q)
            expected.add(VertexPair(q, y))
            expected.add(VertexPair(q, z))
        }
        val actual = UcfsSolver.reachablePairs(withBars(fwd), grammar, starts)
        val t2 = System.nanoTime()
        println("E3GrammarTest manyFields: k=$k rsm=${(t1 - t0) / 1_000_000} ms query=${(t2 - t1) / 1_000_000} ms")
        assertEquals(expected, actual)
    }
}
