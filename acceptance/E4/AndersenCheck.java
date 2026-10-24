import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.BitSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * E4 acceptance oracle (independent of UCFS and of qilin.ucfs): reads a dump written by -ucfspt
 * (graph.dot, vertices.tsv, pts.tsv in one directory) and computes the Andersen fixpoint of the
 * forward edges of graph.dot by itself, with the reading of E3.md D4 (o -new-> v, u -assign-> v,
 * y -store_i-> x for x.f_i = y, x -load_i-> z for z = x.f_i; "_bar" edges are ignored):
 *   o in pts(v) for o -new-> v;  pts(v) >= pts(u) for u -assign-> v;
 *   pts(o.i) >= pts(y) for y -store_i-> x and o in pts(x);  pts(z) >= pts(o.i) for x -load_i-> z and o in pts(x).
 * No type filter, no special objects. Prints
 *   ANDERSEN vertices <n> objects <n> edges <n> pairs <n> dumped <n>
 *   ANDERSEN equal            (exit 0)   or   ANDERSEN differ ... (exit 1)
 * Usage: java -cp <anything> AndersenCheck.java <dump dir>
 */
public class AndersenCheck {
    public static void main(String[] args) throws Exception {
        Path dir = Path.of(args[0]);
        List<String> labels = new ArrayList<>();
        for (String line : Files.readAllLines(dir.resolve("vertices.tsv"))) {
            if (line.isEmpty()) {
                continue;
            }
            String[] f = line.split("\t", 3);
            int id = Integer.parseInt(f[0]);
            while (labels.size() <= id) {
                labels.add(null);
            }
            labels.set(id, f[1]);
        }
        int n = labels.size();
        int[] objIndex = new int[n];
        int nobj = 0;
        for (int i = 0; i < n; i++) {
            objIndex[i] = labels.get(i) != null && labels.get(i).matches("O\\d+") ? nobj++ : -1;
        }
        int[] objVertex = new int[nobj];
        for (int i = 0; i < n; i++) {
            if (objIndex[i] >= 0) {
                objVertex[objIndex[i]] = i;
            }
        }
        Pattern edge = Pattern.compile("^\\s*(\\d+)\\s*->\\s*(\\d+)\\s*\\[label\\s*=\\s*\"([^\"]*)\"\\];?\\s*$");
        List<int[]> news = new ArrayList<>();
        Map<Integer, List<Integer>> assignOut = new HashMap<>();
        Map<Integer, List<int[]>> storeBySrc = new HashMap<>();  // y -> {x, i}
        Map<Integer, List<int[]>> storeByBase = new HashMap<>(); // x -> {y, i}
        Map<Integer, List<int[]>> loadByBase = new HashMap<>();  // x -> {z, i}
        Map<Integer, List<int[]>> loadByField = new HashMap<>(); // i -> {x, z}
        int edges = 0;
        for (String line : Files.readAllLines(dir.resolve("graph.dot"))) {
            Matcher m = edge.matcher(line);
            if (!m.matches()) {
                continue;
            }
            edges++;
            int u = Integer.parseInt(m.group(1));
            int v = Integer.parseInt(m.group(2));
            String l = m.group(3);
            if (l.endsWith("_bar")) {
                continue;
            }
            if (l.equals("new")) {
                news.add(new int[]{u, v});
            } else if (l.equals("assign")) {
                assignOut.computeIfAbsent(u, k -> new ArrayList<>()).add(v);
            } else if (l.startsWith("store_")) {
                int i = Integer.parseInt(l.substring(6));
                storeBySrc.computeIfAbsent(u, k -> new ArrayList<>()).add(new int[]{v, i});
                storeByBase.computeIfAbsent(v, k -> new ArrayList<>()).add(new int[]{u, i});
            } else if (l.startsWith("load_")) {
                int i = Integer.parseInt(l.substring(5));
                loadByBase.computeIfAbsent(u, k -> new ArrayList<>()).add(new int[]{v, i});
                loadByField.computeIfAbsent(i, k -> new ArrayList<>()).add(new int[]{u, v});
            } else {
                System.out.println("ANDERSEN unknown label " + l);
                System.exit(2);
            }
        }
        BitSet[] pts = new BitSet[n];
        Map<Long, BitSet> fpts = new HashMap<>();
        ArrayDeque<Long> work = new ArrayDeque<>(); // >= 0: vertex; < 0: -(field key) - 1
        for (int[] e : news) {
            if (objIndex[e[0]] < 0) {
                System.out.println("ANDERSEN new edge from a non-object vertex " + e[0]);
                System.exit(2);
            }
            if (pts[e[1]] == null) {
                pts[e[1]] = new BitSet();
            }
            if (!pts[e[1]].get(objIndex[e[0]])) {
                pts[e[1]].set(objIndex[e[0]]);
                work.add((long) e[1]);
            }
        }
        while (!work.isEmpty()) {
            long w = work.poll();
            if (w < 0) {
                long key = -w - 1;
                int o = (int) (key >>> 32);
                int i = (int) key;
                BitSet cur = fpts.get(key);
                for (int[] xz : loadByField.getOrDefault(i, List.of())) {
                    if (pts[xz[0]] != null && pts[xz[0]].get(o)) {
                        flow(pts, xz[1], cur, work);
                    }
                }
                continue;
            }
            int v = (int) w;
            BitSet cur = (BitSet) pts[v].clone();
            for (int to : assignOut.getOrDefault(v, List.of())) {
                flow(pts, to, cur, work);
            }
            for (int[] xi : storeBySrc.getOrDefault(v, List.of())) {
                BitSet bases = pts[xi[0]];
                if (bases != null) {
                    for (int o = bases.nextSetBit(0); o >= 0; o = bases.nextSetBit(o + 1)) {
                        fflow(fpts, o, xi[1], cur, work);
                    }
                }
            }
            for (int[] yi : storeByBase.getOrDefault(v, List.of())) {
                BitSet ys = pts[yi[0]];
                if (ys != null) {
                    for (int o = cur.nextSetBit(0); o >= 0; o = cur.nextSetBit(o + 1)) {
                        fflow(fpts, o, yi[1], ys, work);
                    }
                }
            }
            for (int[] zi : loadByBase.getOrDefault(v, List.of())) {
                for (int o = cur.nextSetBit(0); o >= 0; o = cur.nextSetBit(o + 1)) {
                    BitSet f = fpts.get(((long) o << 32) | (zi[1] & 0xffffffffL));
                    if (f != null) {
                        flow(pts, zi[0], f, work);
                    }
                }
            }
        }
        TreeSet<String> mine = new TreeSet<>();
        for (int v = 0; v < n; v++) {
            if (pts[v] != null && objIndex[v] < 0) {
                for (int o = pts[v].nextSetBit(0); o >= 0; o = pts[v].nextSetBit(o + 1)) {
                    mine.add(labels.get(v) + "\t" + labels.get(objVertex[o]));
                }
            }
        }
        TreeSet<String> dumped = new TreeSet<>();
        for (String line : Files.readAllLines(dir.resolve("pts.tsv"))) {
            if (!line.isEmpty()) {
                dumped.add(line);
            }
        }
        System.out.println("ANDERSEN vertices " + n + " objects " + nobj + " edges " + edges + " pairs " + mine.size()
                + " dumped " + dumped.size());
        if (mine.equals(dumped)) {
            System.out.println("ANDERSEN equal");
            return;
        }
        TreeSet<String> a = new TreeSet<>(mine);
        a.removeAll(dumped);
        TreeSet<String> b = new TreeSet<>(dumped);
        b.removeAll(mine);
        System.out.println("ANDERSEN differ only-andersen=" + a.size() + " " + a.stream().limit(5).toList()
                + " only-dump=" + b.size() + " " + b.stream().limit(5).toList());
        System.exit(1);
    }

    static void flow(BitSet[] pts, int to, BitSet objs, ArrayDeque<Long> work) {
        if (pts[to] == null) {
            pts[to] = new BitSet();
        }
        BitSet before = (BitSet) pts[to].clone();
        pts[to].or(objs);
        if (!pts[to].equals(before)) {
            work.add((long) to);
        }
    }

    static void fflow(Map<Long, BitSet> fpts, int o, int i, BitSet objs, ArrayDeque<Long> work) {
        long key = ((long) o << 32) | (i & 0xffffffffL);
        BitSet s = fpts.computeIfAbsent(key, k -> new BitSet());
        int before = s.cardinality();
        s.or(objs);
        if (s.cardinality() != before) {
            work.add(-key - 1);
        }
    }
}
