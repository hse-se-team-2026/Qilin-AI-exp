package qilin.pta.ucfs;

import kotlin.Pair;
import qilin.core.PTA;
import qilin.core.pag.AllocNode;
import qilin.core.pag.ArrayElement;
import qilin.core.pag.Node;
import qilin.pta.PTAConfig;
import qilin.ucfs.idr.IdrCalls;
import qilin.ucfs.idr.IdrExport;
import qilin.ucfs.idr.IdrGraph;
import qilin.ucfs.idr.IdrResult;
import qilin.ucfs.idr.IdrSolve;
import qilin.ucfs.idr.IdrVertex;
import qilin.util.PTAUtils;
import soot.jimple.spark.pag.SparkField;

import java.io.File;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Runs cfl-idr-with-gll in the JVM of Qilin on the IDR export of a finished analysis and dumps the graph
 * and the answer, so that the unchanged CLI of cfl-idr can be run on the same graph (E6-S5; E6.md D2, D7 (e),
 * D14). Called by driver.Main when the option -cflidr=&lt;grammar&gt; is set; without it driver.Main does not
 * call it and no class of qilin.ucfs.idr or cfl-idr is loaded. It reads the PAG and does not change the
 * analysis.
 *
 * <p><b>Thread.</b> The export ({@link IdrExport#export}, mode {@code -cflidrmode}), cfl-idr
 * ({@link IdrSolve#solve}, grammar {@code -cflidr}) and the dump run in a new thread {@value #THREAD_NAME}
 * with the stack size {@code -cflidrstack} (1 GB by default; cfl-idr recurses deeply when it builds and runs
 * the grammars of many bracket kinds, and a stack of 1 MB is a limit of the run, not of the method, E6.md
 * D10, MAJOR-3 of critic-E6). The calling thread waits for it ({@link #runOnThread}). If the thread throws
 * anything ({@code StackOverflowError}, {@code OutOfMemoryError}, an exception), Qilin prints the report of
 * {@link #report} and halts the JVM at once with exit code {@value #EXIT_FAILED}: otherwise the timer thread
 * of {@code qilin.util.MemoryWatcher} keeps the JVM alive until an outer timeout.
 *
 * <p><b>Lines</b> (stdout, each flushed when printed, so that a run that stops shows how far it got):
 * <ul>
 *   <li>{@code #CFLIDR-stack} (bytes), before the thread starts;</li>
 *   <li>after the export, before cfl-idr: {@code #CFLIDR-mode}, {@code -grammar}, {@code -vertices},
 *       {@code -edges}, {@code -fields}, {@code -sites} (sizes of the {@link IdrGraph}) and
 *       {@code #CFLIDR-export-ms};</li>
 *   <li>{@code #CFLIDR-input-ms}, {@code -under-ms}, {@code -over-ms} and, with {@code parityD} and
 *       {@code on-demand}, {@code -ondemand-ms}, each as soon as its phase ends (the {@code onPhase} of
 *       {@link IdrSolve#solve});</li>
 *   <li>after the dump: {@code #CFLIDR-under-pairs}, {@code -over-pairs} (vertex pairs of the answer), with
 *       {@code parityD}/{@code on-demand} {@code -ondemand-pairs}, then {@code #CFLIDR-pt-under},
 *       {@code -pt-over} (and {@code -pt-ondemand}): the points-to pairs of those answers
 *       ({@link IdrExport#pointsTo}). {@code #CFLIDR-pt-over} is printed only by a run that finished.</li>
 * </ul>
 *
 * <p><b>Dump</b> in {@code <outDir>/cflidr} (outDir of {@code PTAConfig}, sootOutput by default):
 * <ul>
 *   <li>{@code graph.dot}: the graph as the CLI of cfl-idr reads it ({@link IdrExport#writeDot});</li>
 *   <li>{@code vertices.tsv}: {@code id<TAB>layer<TAB>label<TAB>node} per vertex id, {@code label} is
 *       {@link PTAUtils#getNodeLabel} of the CI node and {@code node} its {@code toString()} with runs of white
 *       space replaced by one space;</li>
 *   <li>{@code fields.tsv} ({@code index<TAB>field}, {@code ArrayElement} for the array element) and
 *       {@code sites.tsv} ({@code index<TAB>call statement}): the indices of the labels;</li>
 *   <li>{@code counters.tsv}: {@code key<TAB>value} of {@link IdrGraph#getCounters()};</li>
 *   <li>{@code under.tsv}, {@code over.tsv} (and {@code ondemand.tsv}): {@code source<TAB>target} vertex ids
 *       per pair of the answer;</li>
 *   <li>{@code pts-under.tsv}, {@code pts-over.tsv} (and {@code pts-ondemand.tsv}): {@code variable<TAB>object}
 *       per points-to pair, both as in the column {@code node} of {@code vertices.tsv}.</li>
 * </ul>
 * All files are sorted (pairs by ids, points-to lines as strings).
 */
public final class CflIdrRun {
    /** Name of the thread that runs the export, cfl-idr and the dump. */
    public static final String THREAD_NAME = "cflidr";

    /** Exit code of Qilin when the thread of cfl-idr fails (not 0, nor 124/137 of timeout). */
    public static final int EXIT_FAILED = 3;

    /** Number of top frames of the throwable in the failure report. */
    public static final int REPORT_FRAMES = 20;

    /** Grammars of {@link IdrSolve#solve} that add the on-demand refinement (phase {@code ondemand}). */
    private static final List<String> ON_DEMAND = List.of("parityD", "on-demand");

    private CflIdrRun() {
    }

    /**
     * Exports the PAG of {@code pta} in the mode {@code PTAConfig.cflIdrMode}, runs cfl-idr with
     * {@code PTAConfig.cflIdrGrammar}, writes the dump and prints the lines, in a thread with
     * {@code PTAConfig.cflIdrStack} bytes of stack. Returns when the thread has finished; if it failed,
     * prints {@link #report} and halts the JVM with {@value #EXIT_FAILED}. Call it after {@code pta.run()}.
     */
    public static void run(PTA pta) {
        PTAConfig config = PTAConfig.v();
        String grammar = config.cflIdrGrammar;
        String mode = config.cflIdrMode;
        long stack = config.cflIdrStack;
        line("#CFLIDR-stack: " + stack);
        AtomicReference<String> phase = new AtomicReference<>("export");
        Throwable failure = runOnThread(stack, () -> exportSolveDump(pta, IdrCalls.valueOf(mode), grammar, phase));
        if (failure != null) {
            System.out.print(report(failure, phase.get()));
            System.out.flush();
            System.err.flush();
            Runtime.getRuntime().halt(EXIT_FAILED);
        }
    }

    /**
     * Runs {@code body} in a new thread {@value #THREAD_NAME} with {@code stackBytes} bytes of stack
     * ({@code new Thread(null, r, name, stackBytes)}) and waits until it ends.
     *
     * @return what {@code body} threw (any {@code Throwable}), or {@code null} if it returned normally
     */
    public static Throwable runOnThread(long stackBytes, Runnable body) {
        AtomicReference<Throwable> failure = new AtomicReference<>();
        AtomicBoolean finished = new AtomicBoolean();
        Thread thread = new Thread(null, () -> {
            try {
                body.run();
                finished.set(true);
            } catch (Throwable t) {
                failure.set(t);
            }
        }, THREAD_NAME, stackBytes);
        thread.start();
        boolean interrupted = false;
        while (true) {
            try {
                thread.join();
                break;
            } catch (InterruptedException e) {
                interrupted = true;
            }
        }
        if (interrupted) {
            Thread.currentThread().interrupt();
        }
        if (failure.get() == null && !finished.get()) {
            return new IllegalStateException("thread " + THREAD_NAME + " ended without finishing and without a throwable");
        }
        return failure.get();
    }

    /**
     * The failure report of the thread: {@code #CFLIDR-error: <class> at <phase>}, {@code #CFLIDR-error-depth: <n>}
     * (length of the stack trace of {@code t}), the line {@code t.toString()} (line breaks as blanks) and the
     * top {@code min(}{@value #REPORT_FRAMES}{@code , n)} frames as {@code \tat <frame>}; each line ends with
     * a line break. {@code phase} is the phase the thread was in: {@code export}, {@code input}, {@code under},
     * {@code over}, {@code ondemand}, {@code result} (points-to of the answer) or {@code dump}.
     */
    public static String report(Throwable t, String phase) {
        StackTraceElement[] trace = t.getStackTrace();
        StringBuilder sb = new StringBuilder();
        sb.append("#CFLIDR-error: ").append(t.getClass().getName()).append(" at ").append(phase).append('\n');
        sb.append("#CFLIDR-error-depth: ").append(trace.length).append('\n');
        sb.append(String.valueOf(t).replaceAll("[\\r\\n]+", " ")).append('\n');
        for (int i = 0; i < Math.min(REPORT_FRAMES, trace.length); i++) {
            sb.append("\tat ").append(trace[i]).append('\n');
        }
        return sb.toString();
    }

    private static void exportSolveDump(PTA pta, IdrCalls calls, String grammar, AtomicReference<String> phase) {
        long start = System.nanoTime();
        IdrGraph g = IdrExport.export(pta, calls);
        long exportMs = (System.nanoTime() - start) / 1_000_000;
        line("#CFLIDR-mode: " + calls.name());
        line("#CFLIDR-grammar: " + grammar);
        line("#CFLIDR-vertices: " + g.getVertices().size());
        line("#CFLIDR-edges: " + g.getEdges().size());
        line("#CFLIDR-fields: " + g.getFields().size());
        line("#CFLIDR-sites: " + g.getSites().size());
        line("#CFLIDR-export-ms: " + exportMs);

        boolean onDemand = ON_DEMAND.contains(grammar);
        phase.set("input");
        IdrResult r = IdrSolve.solve(g, grammar, (key, ms) -> {
            line("#CFLIDR-" + key + ": " + ms);
            phase.set(switch (key) {
                case "input-ms" -> "under";
                case "under-ms" -> "over";
                case "over-ms" -> onDemand ? "ondemand" : "result";
                default -> "result";
            });
        });

        phase.set("result");
        List<String> under = pairLines(r.getUnder());
        List<String> over = pairLines(r.getOver());
        List<String> ptsUnder = ptsLines(IdrExport.pointsTo(g, r.getUnder()));
        List<String> ptsOver = ptsLines(IdrExport.pointsTo(g, r.getOver()));
        List<String> ondemand = r.getOnDemand() == null ? null : pairLines(r.getOnDemand());
        List<String> ptsOndemand = r.getOnDemand() == null ? null : ptsLines(IdrExport.pointsTo(g, r.getOnDemand()));

        phase.set("dump");
        File dir = new File(PTAConfig.v().getOutConfig().outDir, "cflidr");
        if (!dir.isDirectory() && !dir.mkdirs()) {
            throw new UncheckedIOException(new IOException("cannot create directory " + dir));
        }
        IdrExport.writeDot(g, new File(dir, "graph.dot"));
        write(new File(dir, "vertices.tsv"), vertexLines(g));
        write(new File(dir, "fields.tsv"), fieldLines(g));
        write(new File(dir, "sites.tsv"), siteLines(g));
        write(new File(dir, "counters.tsv"), counterLines(g));
        write(new File(dir, "under.tsv"), under);
        write(new File(dir, "over.tsv"), over);
        write(new File(dir, "pts-under.tsv"), ptsUnder);
        write(new File(dir, "pts-over.tsv"), ptsOver);
        writeOrDelete(new File(dir, "ondemand.tsv"), ondemand);
        writeOrDelete(new File(dir, "pts-ondemand.tsv"), ptsOndemand);

        line("#CFLIDR-under-pairs: " + under.size());
        line("#CFLIDR-over-pairs: " + over.size());
        if (ondemand != null) {
            line("#CFLIDR-ondemand-pairs: " + ondemand.size());
        }
        line("#CFLIDR-pt-under: " + ptsUnder.size());
        line("#CFLIDR-pt-over: " + ptsOver.size());
        if (ptsOndemand != null) {
            line("#CFLIDR-pt-ondemand: " + ptsOndemand.size());
        }
    }

    static List<String> vertexLines(IdrGraph g) {
        List<IdrVertex> vertices = g.getVertices();
        List<String> lines = new ArrayList<>(vertices.size());
        for (int id = 0; id < vertices.size(); id++) {
            IdrVertex v = vertices.get(id);
            lines.add(id + "\t" + v.getLayer() + "\t" + PTAUtils.getNodeLabel(v.getNode()) + "\t" + squeeze(v.getNode().toString()));
        }
        return lines;
    }

    static List<String> fieldLines(IdrGraph g) {
        List<SparkField> fields = g.getFields();
        List<String> lines = new ArrayList<>(fields.size());
        for (int i = 0; i < fields.size(); i++) {
            SparkField f = fields.get(i);
            lines.add(i + "\t" + (f instanceof ArrayElement ? "ArrayElement" : squeeze(f.toString())));
        }
        return lines;
    }

    static List<String> siteLines(IdrGraph g) {
        List<soot.Unit> sites = g.getSites();
        List<String> lines = new ArrayList<>(sites.size());
        for (int i = 0; i < sites.size(); i++) {
            lines.add(i + "\t" + squeeze(sites.get(i).toString()));
        }
        return lines;
    }

    static List<String> counterLines(IdrGraph g) {
        List<String> lines = new ArrayList<>();
        g.getCounters().forEach((k, v) -> lines.add(k + "\t" + v));
        return lines;
    }

    /** {@code source<TAB>target} per pair, ordered by source, then target. */
    static List<String> pairLines(Collection<Pair<Integer, Integer>> pairs) {
        List<Pair<Integer, Integer>> sorted = new ArrayList<>(pairs);
        sorted.sort((a, b) -> a.getFirst().equals(b.getFirst())
                ? Integer.compare(a.getSecond(), b.getSecond()) : Integer.compare(a.getFirst(), b.getFirst()));
        List<String> lines = new ArrayList<>(sorted.size());
        for (Pair<Integer, Integer> p : sorted) {
            lines.add(p.getFirst() + "\t" + p.getSecond());
        }
        return lines;
    }

    /** {@code variable<TAB>object} per points-to pair (nodes as in vertices.tsv), sorted. */
    static List<String> ptsLines(Map<Node, ? extends Set<? extends AllocNode>> pts) {
        List<String> lines = new ArrayList<>();
        pts.forEach((v, objs) -> {
            String var = squeeze(v.toString());
            for (AllocNode o : objs) {
                lines.add(var + "\t" + squeeze(o.toString()));
            }
        });
        lines.sort(null);
        return lines;
    }

    private static void line(String s) {
        System.out.println(s);
        System.out.flush();
    }

    private static String squeeze(String s) {
        return s.replaceAll("\\s+", " ");
    }

    private static void writeOrDelete(File file, List<String> lines) {
        if (lines != null) {
            write(file, lines);
        } else {
            try {
                Files.deleteIfExists(file.toPath());
            } catch (IOException e) {
                throw new UncheckedIOException(e);
            }
        }
    }

    private static void write(File file, List<String> lines) {
        try {
            Files.write(file.toPath(), lines, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
