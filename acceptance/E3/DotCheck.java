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
 * equal pts.tsv, and every start vertex of the DOT file is an allocation vertex; exit 1 otherwise.
 */
public class DotCheck {
    public static void main(String[] args) throws Exception {
        Path dir = Path.of(args[0]);
        InputGraph<Integer, TerminalInputLabel> g = new DotParser().parseDotFile(dir.resolve("graph.dot").toString());
        Map<Integer, String> label = new HashMap<>();
        for (String line : Files.readAllLines(dir.resolve("vertices.tsv"))) {
            String[] f = line.split("\t", 3);
            label.put(Integer.parseInt(f[0]), f[1]);
        }
        int fields = Files.readAllLines(dir.resolve("fields.tsv")).size();
        int edges = 0;
        for (List<Edge<Integer, TerminalInputLabel>> out : g.getEdges().values()) {
            edges += out.size();
        }
        boolean ok = true;
        for (int s : g.getStartVertices()) {
            if (!label.getOrDefault(s, "?").startsWith("O")) {
                System.out.println("DOTCHECK bad-start-vertex " + s + " " + label.get(s));
                ok = false;
            }
        }
        long allocVertices = label.values().stream().filter(l -> l.startsWith("O")).count();
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
        if (g.getStartVertices().size() != allocVertices) {
            ok = false;
        }
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
