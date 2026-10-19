import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import org.ucfs.input.DotParser;
import org.ucfs.input.Edge;
import org.ucfs.input.InputGraph;
import org.ucfs.input.TerminalInputLabel;
import org.ucfs.parser.Gll;
import org.ucfs.sppf.node.RangeSppfNode;
import qilin.ucfs.grammar.PointsToGrammar;

/**
 * E3-S4 acceptance helper (docs/ai/tickets/E3-S4.md), run as a single-file program with the
 * fat jar on the class path: java -cp qilin-fat.jar acceptance/E3/DotCheck.java <dir>.
 *
 * <p>Reads the dump of -ucfspt (<dir>/graph.dot, vertices.tsv, fields.tsv, pts.tsv) as an external
 * consumer would: the graph through UCFS's own DOT reader (org.ucfs.input.DotParser), the query
 * through Gll directly (not through qilin.ucfs.UcfsSolver or UcfsPointsTo). Prints one line
 * "DOTCHECK <key> <value>" per fact and exits 0 when the pairs (object, variable) found this way
 * equal pts.tsv, the ids of vertices.tsv are exactly 0..n-1 with no repetition, and the set of
 * start vertices of the DOT file equals the set of ids whose label is an object label O<n>
 * (the allocation vertices); exit 1 otherwise.
 */
public class DotCheck {
    public static void main(String[] args) throws Exception {
        Path dir = Path.of(args[0]);
        InputGraph<Integer, TerminalInputLabel> g = new DotParser().parseDotFile(dir.resolve("graph.dot").toString());
        Map<Integer, String> label = new HashMap<>();
        int lines = 0;
        boolean idsOk = true;
        for (String line : Files.readAllLines(dir.resolve("vertices.tsv"))) {
            String[] f = line.split("\t", 3);
            if (label.put(Integer.parseInt(f[0]), f[1]) != null) {
                idsOk = false;
            }
            lines++;
        }
        for (int i = 0; i < lines; i++) {
            idsOk &= label.containsKey(i);
        }
        int fields = Files.readAllLines(dir.resolve("fields.tsv")).size();
        int edges = 0;
        for (List<Edge<Integer, TerminalInputLabel>> out : g.getEdges().values()) {
            edges += out.size();
        }
        boolean ok = idsOk;
        if (!idsOk) {
            System.out.println("DOTCHECK bad-vertex-ids: vertices.tsv ids are not exactly 0.." + (lines - 1));
        }
        Set<Integer> allocIds = new TreeSet<>();
        label.forEach((id, l) -> {
            if (l.matches("O\\d+")) {
                allocIds.add(id);
            }
        });
        Set<Integer> starts = new TreeSet<>(g.getStartVertices());
        if (!starts.equals(allocIds)) {
            Set<Integer> a = new TreeSet<>(starts);
            a.removeAll(allocIds);
            Set<Integer> b = new TreeSet<>(allocIds);
            b.removeAll(starts);
            System.out.println("DOTCHECK start-vertices-not-allocation " + a);
            System.out.println("DOTCHECK allocation-vertices-not-start " + b);
            ok = false;
        }
        long allocVertices = allocIds.size();
        Set<RangeSppfNode<Integer>> roots = Gll.Companion.gll(new PointsToGrammar(fields).getRsm(), g).parse();
        Set<String> pairs = new TreeSet<>();
        for (RangeSppfNode<Integer> r : roots) {
            String o = label.get(r.getInputRange().getFrom());
            String v = label.get(r.getInputRange().getTo());
            if (o != null && v != null && o.startsWith("O") && !v.startsWith("O")) {
                pairs.add(v + "\t" + o);
            }
        }
        Set<String> dumped = new TreeSet<>(Files.readAllLines(dir.resolve("pts.tsv")));
        dumped.remove("");
        System.out.println("DOTCHECK vertices " + label.size());
        System.out.println("DOTCHECK edges " + edges);
        System.out.println("DOTCHECK fields " + fields);
        System.out.println("DOTCHECK start-vertices " + g.getStartVertices().size() + " alloc-vertices " + allocVertices);
        System.out.println("DOTCHECK pairs " + pairs.size() + " dumped " + dumped.size());
        if (!pairs.equals(dumped)) {
            Set<String> a = new TreeSet<>(pairs);
            a.removeAll(dumped);
            Set<String> b = new TreeSet<>(dumped);
            b.removeAll(pairs);
            System.out.println("DOTCHECK only-in-dot-run " + a);
            System.out.println("DOTCHECK only-in-pts.tsv " + b);
            ok = false;
        }
        System.out.println("DOTCHECK result " + (ok ? "OK" : "MISMATCH"));
        System.exit(ok ? 0 : 1);
    }
}
