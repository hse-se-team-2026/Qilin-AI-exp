import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.BitSet;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * E6 acceptance (docs/ai/tickets/E6-S6.md): an independent solver for the FIELDS export dumped by
 * -cflidr (-cflidrmode=ERASED). It reads <dump>/graph.dot (edges u->v[label="l"]) and
 * <dump>/vertices.tsv (id, layer, label, node) and computes Dyck reachability with one kind family
 * (S -> eps | normal S | ob--i S cb--i S, per bracket id i) by a fixpoint over bit sets, without UCFS,
 * GLL or cfl-idr. With only brackets the interleaved Dyck language is this Dyck language, so cfl-idr's
 * under- and over-approximation must both equal it. Pairs: from an OBJ vertex to an F vertex,
 * printed as "node-of-F<TAB>node-of-OBJ" and compared with <dump>/pts-over.tsv and pts-under.tsv.
 * Usage: java acceptance/E6/IdrDyckCheck.java <dump-dir>      (exit 0 = equal)
 */
public class IdrDyckCheck {
    record E(int from, String label, int to) {
    }

    public static void main(String[] args) throws IOException {
        Path dir = Path.of(args[0]);
        Pattern edge = Pattern.compile("^\\s*(\\d+)\\s*->\\s*(\\d+)\\s*\\[label=\"([^\"]+)\"\\];?\\s*$");
        List<E> edges = new ArrayList<>();
        for (String l : Files.readAllLines(dir.resolve("graph.dot"))) {
            Matcher m = edge.matcher(l);
            if (m.matches()) {
                edges.add(new E(Integer.parseInt(m.group(1)), m.group(3), Integer.parseInt(m.group(2))));
            }
        }
        List<String[]> verts = new ArrayList<>();
        for (String l : Files.readAllLines(dir.resolve("vertices.tsv"))) {
            verts.add(l.split("\t", -1));
        }
        int n = verts.size();
        List<List<Integer>> normal = new ArrayList<>();
        List<Map<String, List<Integer>>> open = new ArrayList<>();
        List<Map<String, List<Integer>>> close = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            normal.add(new ArrayList<>());
            open.add(new HashMap<>());
            close.add(new HashMap<>());
        }
        for (E e : edges) {
            if (e.label().equals("normal")) {
                normal.get(e.from()).add(e.to());
            } else if (e.label().startsWith("ob--")) {
                open.get(e.from()).computeIfAbsent(e.label().substring(4), k -> new ArrayList<>()).add(e.to());
            } else if (e.label().startsWith("cb--")) {
                close.get(e.from()).computeIfAbsent(e.label().substring(4), k -> new ArrayList<>()).add(e.to());
            } else {
                System.out.println("FAIL: label " + e.label() + " is not a FIELDS label");
                System.exit(1);
            }
        }
        // R[u] = { v : u reaches v by a balanced word }; R[u] = {u} + R[w] for normal u->w
        // + R[z] for ob--i u->x, y in R[x], cb--i y->z
        BitSet[] r = new BitSet[n];
        for (int i = 0; i < n; i++) {
            r[i] = new BitSet(n);
            r[i].set(i);
        }
        boolean changed = true;
        int passes = 0;
        while (changed) {
            changed = false;
            passes++;
            for (int u = n - 1; u >= 0; u--) {
                BitSet before = (BitSet) r[u].clone();
                for (int w : normal.get(u)) {
                    r[u].or(r[w]);
                }
                for (Map.Entry<String, List<Integer>> oe : open.get(u).entrySet()) {
                    for (int x : oe.getValue()) {
                        for (int y = r[x].nextSetBit(0); y >= 0; y = r[x].nextSetBit(y + 1)) {
                            for (int z : close.get(y).getOrDefault(oe.getKey(), List.of())) {
                                r[u].or(r[z]);
                            }
                        }
                    }
                }
                if (!r[u].equals(before)) {
                    changed = true;
                }
            }
        }
        Set<String> pts = new HashSet<>();
        for (int u = 0; u < n; u++) {
            if (!verts.get(u)[1].equals("OBJ")) {
                continue;
            }
            for (int v = r[u].nextSetBit(0); v >= 0; v = r[u].nextSetBit(v + 1)) {
                if (verts.get(v)[1].equals("F")) {
                    pts.add(verts.get(v)[3] + "\t" + verts.get(u)[3]);
                }
            }
        }
        boolean ok = true;
        for (String f : List.of("pts-under.tsv", "pts-over.tsv")) {
            Set<String> got = new HashSet<>(Files.readAllLines(dir.resolve(f)));
            Set<String> missing = new HashSet<>(pts);
            missing.removeAll(got);
            Set<String> extra = new HashSet<>(got);
            extra.removeAll(pts);
            boolean eq = missing.isEmpty() && extra.isEmpty();
            ok &= eq;
            System.out.println((eq ? "PASS: " : "FAIL: ") + f + " = Dyck reachability of graph.dot (" + pts.size()
                    + " pairs; missing " + missing.size() + ", extra " + extra.size() + ")");
        }
        System.out.println("IdrDyckCheck vertices=" + n + " edges=" + edges.size() + " passes=" + passes);
        System.exit(ok ? 0 : 1);
    }
}
