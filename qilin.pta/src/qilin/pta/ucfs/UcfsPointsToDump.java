package qilin.pta.ucfs;

import org.ucfs.input.InputGraph;
import org.ucfs.input.TerminalInputLabel;
import org.ucfs.input.utils.DotWriter;
import org.ucfs.rsm.symbol.Term;
import qilin.core.PTA;
import qilin.core.pag.AllocNode;
import qilin.core.pag.Node;
import qilin.core.pag.VarNode;
import qilin.pta.PTAConfig;
import qilin.ucfs.LabeledEdge;
import qilin.ucfs.PagExport;
import qilin.ucfs.UcfsGraph;
import qilin.ucfs.UcfsPointsTo;
import qilin.ucfs.grammar.PointsToGrammar;
import qilin.util.PTAUtils;
import soot.jimple.spark.pag.SparkField;

import java.io.File;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;

/**
 * Runs the UCFS points-to query of qilin.ucfs ({@link UcfsPointsTo}) on a finished analysis and
 * dumps the input graph and the answer for a run of UCFS outside Qilin (E3-S4). Called by
 * driver.Main when the option -ucfspt is set; without the option driver.Main does not call it.
 * It reads the PAG and does not change the analysis.
 *
 * <p>The graph is the main mode of the export, {@code PagExport.export(pta)}
 * ({@code ReceiverBinding.ANALYSIS}); the answer is {@code UcfsPointsTo.solve(graph,
 * new PointsToGrammar(#fields))}, the query of {@code UcfsPointsTo.solve(pta)} on that graph.
 * Files in {@code <outDir>/ucfs} (outDir of {@code PTAConfig}, sootOutput by default):
 * <ul>
 *   <li>{@code graph.dot}: the graph in the DOT format of UCFS ({@code org.ucfs.input.utils.DotWriter},
 *       read back by {@code org.ucfs.input.DotParser}); the start vertices are the object vertices;</li>
 *   <li>{@code vertices.tsv}: {@code id<TAB>label<TAB>node} per vertex id, {@code label} is
 *       {@link PTAUtils#getNodeLabel} of the CI node and {@code node} its {@code toString()} with
 *       runs of white space replaced by one space;</li>
 *   <li>{@code fields.tsv}: {@code index<TAB>field} per field index of the labels store_i/load_i;</li>
 *   <li>{@code pts.tsv}: {@code var-label<TAB>object-label} per pair of the answer.</li>
 * </ul>
 * Prints the five lines {@code #UCFS-pt-vertices}, {@code -edges} (forward and reversed edges),
 * {@code -fields}, {@code -pairs} and {@code -time-ms} (wall time of the export and the solve,
 * without writing the files).
 */
public final class UcfsPointsToDump {
    private UcfsPointsToDump() {
    }

    /** Runs the export and UCFS on {@code pta}, writes the four files and prints the five lines. Call it after {@code pta.run()}. */
    public static void run(PTA pta) {
        long start = System.nanoTime();
        UcfsGraph graph = PagExport.export(pta);
        Map<VarNode, Set<AllocNode>> pts = UcfsPointsTo.solve(graph, new PointsToGrammar(graph.getFields().size()));
        long timeMs = (System.nanoTime() - start) / 1_000_000;

        File dir = new File(PTAConfig.v().getOutConfig().outDir, "ucfs");
        if (!dir.isDirectory() && !dir.mkdirs()) {
            throw new UncheckedIOException(new IOException("cannot create directory " + dir));
        }
        write(new File(dir, "graph.dot"), List.of(dot(graph)));
        write(new File(dir, "vertices.tsv"), vertexLines(graph));
        write(new File(dir, "fields.tsv"), fieldLines(graph));
        List<String> pairs = pairLines(graph, pts);
        write(new File(dir, "pts.tsv"), pairs);

        System.out.println("#UCFS-pt-vertices: " + graph.getVertices().size());
        System.out.println("#UCFS-pt-edges: " + graph.getEdges().size());
        System.out.println("#UCFS-pt-fields: " + graph.getFields().size());
        System.out.println("#UCFS-pt-pairs: " + pairs.size());
        System.out.println("#UCFS-pt-time-ms: " + timeMs);
    }

    /** DOT text of {@code graph} as written by UCFS's DotWriter, with the object vertices as start vertices. */
    static String dot(UcfsGraph graph) {
        InputGraph<Integer, TerminalInputLabel> input = new InputGraph<>();
        for (int v = 0; v < graph.getVertices().size(); v++) {
            input.addVertex(v);
        }
        for (int v : graph.allocVertices()) {
            input.addStartVertex(v);
        }
        for (LabeledEdge e : graph.getEdges()) {
            input.addEdge(e.getFrom(), new TerminalInputLabel(new Term<>(e.getLabel())), e.getTo());
        }
        return new DotWriter().getDotView(input, true);
    }

    static List<String> vertexLines(UcfsGraph graph) {
        List<Node> vertices = graph.getVertices();
        List<String> lines = new ArrayList<>(vertices.size());
        for (int id = 0; id < vertices.size(); id++) {
            Node node = vertices.get(id);
            lines.add(id + "\t" + PTAUtils.getNodeLabel(node) + "\t" + squeeze(node.toString()));
        }
        return lines;
    }

    static List<String> fieldLines(UcfsGraph graph) {
        List<SparkField> fields = graph.getFields();
        List<String> lines = new ArrayList<>(fields.size());
        for (int i = 0; i < fields.size(); i++) {
            lines.add(i + "\t" + squeeze(fields.get(i).toString()));
        }
        return lines;
    }

    /** One line per pair (variable, object), ordered by the vertex ids of the variable and the object. */
    static List<String> pairLines(UcfsGraph graph, Map<VarNode, Set<AllocNode>> pts) {
        TreeMap<Integer, TreeSet<Integer>> byId = new TreeMap<>();
        pts.forEach((v, objs) -> {
            TreeSet<Integer> ids = byId.computeIfAbsent(graph.vertexOf(v), k -> new TreeSet<>());
            for (AllocNode o : objs) {
                ids.add(graph.vertexOf(o));
            }
        });
        List<String> lines = new ArrayList<>();
        byId.forEach((v, objs) -> {
            String varLabel = PTAUtils.getNodeLabel(graph.nodeOf(v));
            for (int o : objs) {
                lines.add(varLabel + "\t" + PTAUtils.getNodeLabel(graph.nodeOf(o)));
            }
        });
        return lines;
    }

    private static String squeeze(String s) {
        return s.replaceAll("\\s+", " ");
    }

    private static void write(File file, List<String> lines) {
        try {
            Files.write(file.toPath(), lines, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
