package qilin.test.ucfs;

import static org.junit.Assert.assertEquals;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import org.junit.Test;
import org.ucfs.input.InputGraph;
import org.ucfs.input.TerminalInputLabel;
import org.ucfs.parser.Gll;
import org.ucfs.rsm.RsmState;
import org.ucfs.rsm.symbol.Nonterminal;
import org.ucfs.rsm.symbol.Term;
import org.ucfs.sppf.node.RangeSppfNode;

/**
 * E1-S4 acceptance check: Qilin resolves the published UCFS artifact (org.ucfs:solver) together
 * with its runtime dependencies and can call the solver from Java.
 *
 * <p>Grammar S -> a S? b (a^n b^n), built by hand as an RSM so that no Kotlin DSL is needed.
 * On the path 0 -a-> 1 -a-> 2 -b-> 3 -b-> 4 the reachable pairs are (0,4) and (1,3).
 */
public class UcfsDependencySmokeTest {

    /** Fixed by the E1 plan (docs/ai/tickets/E1.md). */
    private static final String EXPECTED_UCFS_VERSION = "0.1.0-ai-SNAPSHOT";

    private static final Set<List<Integer>> EXPECTED_PAIRS = Set.of(List.of(0, 4), List.of(1, 3));

    /** Returns the start state of the fictive start nonterminal, as Grammar.rsm does. */
    private static RsmState anbnRsm() {
        Nonterminal s = new Nonterminal("S");
        RsmState s0 = new RsmState(s, true, false, s.getNextRsmStateId());
        RsmState s1 = new RsmState(s, false, false, s.getNextRsmStateId());
        RsmState s2 = new RsmState(s, false, false, s.getNextRsmStateId());
        RsmState s3 = new RsmState(s, false, true, s.getNextRsmStateId());
        s.setStartState(s0);
        s0.addEdge(new Term<>("a"), s1);
        s1.addEdge(s, s2);
        s1.addEdge(new Term<>("b"), s3);
        s2.addEdge(new Term<>("b"), s3);

        Nonterminal start = new Nonterminal("fictiveStart");
        RsmState f0 = new RsmState(start, true, false, start.getNextRsmStateId());
        RsmState f1 = new RsmState(start, false, true, start.getNextRsmStateId());
        start.setStartState(f0);
        f0.addEdge(s, f1);
        return f0;
    }

    private static Set<List<Integer>> pairs(Set<RangeSppfNode<Integer>> roots) {
        Set<List<Integer>> result = new HashSet<>();
        for (RangeSppfNode<Integer> root : roots) {
            result.add(List.of(root.getInputRange().getFrom(), root.getInputRange().getTo()));
        }
        return result;
    }

    @Test
    public void solvesAnBnOnHandBuiltGraph() {
        InputGraph<Integer, TerminalInputLabel> graph = new InputGraph<>();
        String[] labels = {"a", "a", "b", "b"};
        for (int v = 0; v <= labels.length; v++) {
            graph.addStartVertex(v);
        }
        for (int v = 0; v < labels.length; v++) {
            graph.addEdge(v, new TerminalInputLabel(new Term<>(labels[v])), v + 1);
        }
        assertEquals(EXPECTED_PAIRS, pairs(Gll.Companion.gll(anbnRsm(), graph).parse()));
    }

    @Test
    public void solvesAnBnOnDotInput() {
        // DotParser needs the antlr4 runtime, so this also checks transitive runtime deps.
        String dot = "digraph G {\n"
                + "    start -> 0;\n"
                + "    start -> 1;\n"
                + "    0 -> 1 [label = \"a\"];\n"
                + "    1 -> 2 [label = \"a\"];\n"
                + "    2 -> 3 [label = \"b\"];\n"
                + "    3 -> 4 [label = \"b\"];\n"
                + "}";
        InputGraph<Integer, TerminalInputLabel> graph = new org.ucfs.input.DotParser().parseDot(dot);
        assertEquals(EXPECTED_PAIRS, pairs(Gll.Companion.gll(anbnRsm(), graph).parse()));
    }

    @Test
    public void resolvedArtifactIsThePinnedVersion() {
        assertEquals(EXPECTED_UCFS_VERSION, Gll.class.getPackage().getImplementationVersion());
    }
}
