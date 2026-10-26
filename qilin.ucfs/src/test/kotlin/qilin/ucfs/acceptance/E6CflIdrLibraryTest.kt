package qilin.ucfs.acceptance

import org.cfl_idr_with_gll.getMROverApprox
import org.cfl_idr_with_gll.getOnDemandMR
import org.cfl_idr_with_gll.getUnderApprox
import org.cfl_idr_with_gll.models.Path
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.ucfs.input.InputGraph
import org.ucfs.input.TerminalInputLabel
import org.ucfs.rsm.symbol.Term
import java.io.File
import java.net.JarURLConnection
import java.util.Properties

/**
 * E6-S2 acceptance check (docs/ai/tickets/E6-S2.md): Qilin's module qilin.ucfs uses the library
 * cfl-idr-with-gll (org.cfl_idr_with_gll:cfl-idr-with-gll, built from the pinned commit of
 * cfl-idr-with-gll-AI-exp against UCFS-AI-dev by scripts/cflidr/bootstrap.sh) in process, with one
 * UCFS on the class path.
 *
 * The graphs are the figures of Conrado2025Cfl as stored in the cfl-idr repository
 * (src/test/resources/correctness/figure5, figure10), and the expected pairs are the ones its own
 * tests assert (src/test/kotlin/correctness/TestUnderApprox.kt, TestOverApprox.kt): the oracle is
 * the cfl-idr author's, not ours.
 */
class E6CflIdrLibraryTest {

    private fun graph(vararg e: Triple<Int, String, Int>): InputGraph<Int, TerminalInputLabel> {
        val g = InputGraph<Int, TerminalInputLabel>()
        for ((u, l, v) in e) {
            g.addVertex(u)
            g.addVertex(v)
            g.addEdge(u, TerminalInputLabel(Term(l)), v)
        }
        return g
    }

    private fun paths(vararg p: Pair<Int, Int>) = p.map { Path(it.first, it.second) }.toSet()

    // figure10: three nested parentheses and brackets interleaved, closed in the other order
    private fun figure10() = graph(
        Triple(1, "op--1", 2), Triple(1, "ob--1", 2), Triple(2, "op--1", 3), Triple(2, "ob--1", 3),
        Triple(3, "op--1", 4), Triple(3, "ob--1", 4), Triple(4, "op--1", 5), Triple(4, "ob--1", 5),
        Triple(5, "cp--1", 6), Triple(5, "cb--1", 6), Triple(6, "cp--1", 7), Triple(6, "cb--1", 7),
    )

    private fun figure5() = graph(
        Triple(1, "op--1", 2), Triple(2, "cb--1", 3), Triple(3, "ob--1", 4), Triple(4, "cp--1", 5),
        Triple(1, "op--2", 6), Triple(6, "ob--2", 7), Triple(7, "cb--2", 8), Triple(8, "cp--3", 5),
        Triple(8, "cp--2", 9),
    )

    @Test
    fun figure10UnderAndOverApproximations() {
        assertEquals(paths(3 to 7, 4 to 6), getUnderApprox(figure10()))
        assertEquals(
            paths(1 to 3, 1 to 5, 1 to 7, 2 to 4, 2 to 6, 3 to 5, 3 to 7, 4 to 6, 5 to 7),
            getMROverApprox(figure10(), "parity2"),
        )
        assertEquals(paths(1 to 7, 2 to 6, 3 to 7, 4 to 6), getMROverApprox(figure10(), "se"))
        assertEquals(paths(3 to 7, 4 to 6), getMROverApprox(figure10(), "project"))
    }

    @Test
    fun figure5OverApproximationAndOnDemand() {
        assertEquals(paths(1 to 9, 6 to 8), getMROverApprox(figure5(), "parity2"))
        assertEquals(paths(1 to 9, 6 to 8), getMROverApprox(figure5(), "se"))
        val under = getUnderApprox(figure5())
        val over = getMROverApprox(figure5(), "parity", 1, under)
        val onDemand = getOnDemandMR(figure5(), under, over, true)
        assertTrue("under <= on-demand <= over", over.containsAll(onDemand) && onDemand.containsAll(under))
    }

    /** One UCFS on the class path (UCFS-AI-dev from .ucfs/m2) and cfl-idr from .cflidr/m2 at the pinned commit. */
    @Test
    fun oneUcfsAndThePinnedCflIdr() {
        val cl = javaClass.classLoader
        val gll = cl.getResources("org/ucfs/parser/Gll.class").toList()
        assertEquals("exactly one org.ucfs.parser.Gll on the class path: $gll", 1, gll.size)
        assertTrue("UCFS from the project-local .ucfs/m2: ${gll[0]}", gll[0].toString().contains("/.ucfs/m2/org/ucfs/solver/"))

        val approx = cl.getResources("org/cfl_idr_with_gll/ApproximationKt.class").toList()
        assertEquals("exactly one cfl-idr-with-gll on the class path: $approx", 1, approx.size)
        assertTrue("cfl-idr from .cflidr/m2: ${approx[0]}", approx[0].toString().contains("/.cflidr/m2/org/cfl_idr_with_gll/cfl-idr-with-gll/"))
        val conn = approx[0].openConnection() as JarURLConnection
        conn.useCaches = false
        val attrs = conn.jarFile.use { it.manifest.mainAttributes }

        val props = Properties()
        File("../scripts/cflidr/cflidr.properties").reader().use { props.load(it) }
        val gradleProps = Properties()
        File("../gradle.properties").reader().use { gradleProps.load(it) }
        assertEquals("CflIdr-Commit = cflidrCommit", props.getProperty("cflidrCommit"), attrs.getValue("CflIdr-Commit"))
        assertEquals("CflIdr-Dirty", "false", attrs.getValue("CflIdr-Dirty"))
        assertEquals("compiled against ucfsCommit", gradleProps.getProperty("ucfsCommit"), attrs.getValue("UCFS-Commit"))
    }
}
