package qilin.test.ucfs;

import static org.junit.Assert.assertEquals;

import java.util.List;
import java.util.Set;
import org.junit.Test;
import qilin.ucfs.LabeledEdge;
import qilin.ucfs.UcfsSolver;
import qilin.ucfs.VertexPair;
import qilin.ucfs.grammar.AnBnGrammar;

/**
 * E2-S4 acceptance check (docs/ai/tickets/E2-S4.md): Java code of Qilin (module qilin.pta)
 * calls the Kotlin API of module qilin.ucfs. Grammar S -> a S? b; on the path
 * 0 -a-> 1 -a-> 2 -b-> 3 -b-> 4 the reachable pairs are (0,4) and (1,3).
 */
public class E2KotlinInteropTest {

    @Test
    public void javaCallsKotlinSolver() {
        List<LabeledEdge> edges = List.of(
                new LabeledEdge(0, "a", 1),
                new LabeledEdge(1, "a", 2),
                new LabeledEdge(2, "b", 3),
                new LabeledEdge(3, "b", 4));
        Set<VertexPair> pairs = UcfsSolver.reachablePairs(edges, new AnBnGrammar("a", "b"));
        assertEquals(Set.of(new VertexPair(0, 4), new VertexPair(1, 3)), pairs);
    }

    @Test
    public void kotlinDataClassesBehaveAsValuesInJava() {
        LabeledEdge e = new LabeledEdge(7, "load_3", 8);
        assertEquals(7, e.getFrom());
        assertEquals("load_3", e.getLabel());
        assertEquals(8, e.getTo());
        assertEquals(new VertexPair(1, 2), new VertexPair(1, 2));
    }
}
