package qilin.pta.ucfs;

import qilin.core.PTA;
import qilin.ucfs.PagEdge;
import qilin.ucfs.PagEdgeKind;
import qilin.ucfs.QilinPagSeam;

import java.util.EnumMap;
import java.util.Map;
import java.util.Set;

/**
 * Production entry point from Qilin (Java) into the Kotlin module qilin.ucfs: reads the global PAG
 * of a finished analysis through {@link QilinPagSeam#globalEdges(PTA)}. Called by driver.Main when
 * the option -ucfsseam is set. It reads the PAG and prints to stdout; it does not change the
 * analysis and writes no files. E3 is planned to extend this class with the export of the graph
 * to UCFS (E2.md D14).
 */
public final class UcfsSeam {
    private UcfsSeam() {
    }

    /** Number of edges of each kind in {@code edges}; a kind without edges maps to 0. */
    public static Map<PagEdgeKind, Integer> countByKind(Set<PagEdge> edges) {
        Map<PagEdgeKind, Integer> counts = new EnumMap<>(PagEdgeKind.class);
        for (PagEdgeKind kind : PagEdgeKind.values()) {
            counts.put(kind, 0);
        }
        for (PagEdge edge : edges) {
            counts.merge(edge.getKind(), 1, Integer::sum);
        }
        return counts;
    }

    /**
     * Prints the four lines "#UCFS-seam-KIND: n" (KIND = NEW, ASSIGN, LOAD, STORE) with the edge
     * counts of the global PAG of {@code pta}. Call it after {@code pta.run()} has returned.
     */
    public static void printEdgeCounts(PTA pta) {
        Map<PagEdgeKind, Integer> counts = countByKind(QilinPagSeam.globalEdges(pta));
        for (PagEdgeKind kind : PagEdgeKind.values()) {
            System.out.println("#UCFS-seam-" + kind.name() + ": " + counts.get(kind));
        }
    }
}
