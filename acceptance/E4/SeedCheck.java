import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayDeque;
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
 * E4 acceptance oracle for the share of the UCFS answer that Spark seeded (E4.md, lead decision B2),
 * independent of UCFS, of qilin.ucfs and of qilin.pta.ucfs.UcfsCompare. Reads a run of
 * -pta=ucfs -ucfscompare -ucfspt: graph.dot and vertices.tsv of the dump (sootOutput/ucfs) and
 * pairs.tsv of the comparison (sootOutput/ucfs-compare).
 *
 * <p>A seed edge is a forward "new" edge o -> v of graph.dot whose object o is not ROOT (vertex string
 * "AllocNode <n> ROOT ...") and whose variable v is, by its vertices.tsv string,
 * <ul>
 *   <li>this: "LocalVarNode <n> Parm THIS_NODE ...";</li>
 *   <li>exception: "LocalVarNode <n> Parm -3 ..." (throw node) or "LocalVarNode <n> @caughtexception ...";</li>
 *   <li>finalizer: "LocalVarNode <n> Parm 0 to <java.lang.ref.Finalizer: void register(java.lang.Object)>".</li>
 * </ul>
 * Such edges are written by Qilin's solver from Spark's points-to sets, not by allocation statements
 * (E3.md D1). The probe computes the Andersen fixpoint of graph.dot (the reading of AndersenCheck.java)
 * without the "this" seeds and without all seeds and counts the SAME rows of pairs.tsv that survive.
 * Prints one line
 *   SEEDS new <n> this <n> exception <n> finalizer <n> same <n> same-without-this-seeds <n> same-without-seeds <n>
 * Usage: java SeedCheck.java <run dir>            (exit 0; 2 on unreadable input)
 */
public class SeedCheck {
    static final Pattern EDGE = Pattern.compile("^\\s*(\\d+)\\s*->\\s*(\\d+)\\s*\\[label\\s*=\\s*\"([^\"]*)\"\\];?\\s*$");

    public static void main(String[] args) throws Exception {
        Path run = Path.of(args[0]);
        Path dump = run.resolve("sootOutput").resolve("ucfs");
        List<String> labels = new ArrayList<>();
        List<String> kinds = new ArrayList<>();
        Map<String, Integer> byLabel = new HashMap<>();
        for (String line : Files.readAllLines(dump.resolve("vertices.tsv"))) {
            if (line.isEmpty()) {
                continue;
            }
            String[] f = line.split("\t", 3);
            int id = Integer.parseInt(f[0]);
            while (labels.size() <= id) {
                labels.add(null);
                kinds.add("");
            }
            labels.set(id, f[1]);
            kinds.set(id, f[2]);
            byLabel.put(f[1], id);
        }
        int n = labels.size();
        int[] objIndex = new int[n];
        int nobj = 0;
        for (int i = 0; i < n; i++) {
            objIndex[i] = labels.get(i) != null && labels.get(i).matches("O\\d+") ? nobj++ : -1;
        }
        List<int[]> news = new ArrayList<>();
        Map<Integer, List<Integer>> assignOut = new HashMap<>();
        List<int[]> stores = new ArrayList<>(); // {y, x, i}
        List<int[]> loads = new ArrayList<>();  // {x, z, i}
        for (String line : Files.readAllLines(dump.resolve("graph.dot"))) {
            Matcher m = EDGE.matcher(line);
            if (!m.matches()) {
                continue;
            }
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
                stores.add(new int[]{u, v, Integer.parseInt(l.substring(6))});
            } else if (l.startsWith("load_")) {
                loads.add(new int[]{u, v, Integer.parseInt(l.substring(5))});
            } else {
                System.out.println("SEEDS unknown label " + l);
                System.exit(2);
            }
        }
        Pattern root = Pattern.compile("^AllocNode \\d+ ROOT ");
        Pattern pThis = Pattern.compile("^LocalVarNode \\d+ Parm THIS_NODE ");
        Pattern pExc = Pattern.compile("^LocalVarNode \\d+ (Parm -3 |@caughtexception )");
        Pattern pFin = Pattern.compile("^LocalVarNode \\d+ Parm 0 to <java\\.lang\\.ref\\.Finalizer: void register\\(java\\.lang\\.Object\\)>");
        Set<Integer> seedThis = new HashSet<>();
        Set<Integer> seedAll = new HashSet<>();
        int cThis = 0;
        int cExc = 0;
        int cFin = 0;
        for (int k = 0; k < news.size(); k++) {
            int[] e = news.get(k);
            if (root.matcher(kinds.get(e[0])).find()) {
                continue;
            }
            String v = kinds.get(e[1]);
            if (pThis.matcher(v).find()) {
                cThis++;
                seedThis.add(k);
                seedAll.add(k);
            } else if (pExc.matcher(v).find()) {
                cExc++;
                seedAll.add(k);
            } else if (pFin.matcher(v).find()) {
                cFin++;
                seedAll.add(k);
            }
        }
        BitSet[] noThis = fixpoint(n, objIndex, news, seedThis, assignOut, stores, loads);
        BitSet[] noSeeds = fixpoint(n, objIndex, news, seedAll, assignOut, stores, loads);
        int same = 0;
        int keptThis = 0;
        int keptAll = 0;
        for (String line : Files.readAllLines(run.resolve("sootOutput").resolve("ucfs-compare").resolve("pairs.tsv"))) {
            String[] f = line.split("\t");
            if (f.length != 6 || !f[5].equals("SAME")) {
                continue;
            }
            Integer v = byLabel.get(f[0]);
            Integer o = byLabel.get(f[1]);
            if (v == null || o == null || objIndex[o] < 0) {
                System.out.println("SEEDS pairs.tsv row with unknown labels: " + line);
                System.exit(2);
            }
            same++;
            if (noThis[v] != null && noThis[v].get(objIndex[o])) {
                keptThis++;
            }
            if (noSeeds[v] != null && noSeeds[v].get(objIndex[o])) {
                keptAll++;
            }
        }
        System.out.println("SEEDS new " + news.size() + " this " + cThis + " exception " + cExc + " finalizer " + cFin
                + " same " + same + " same-without-this-seeds " + keptThis + " same-without-seeds " + keptAll);
    }

    /** Andersen fixpoint of the forward edges, without the "new" edges whose index is in {@code drop}. */
    static BitSet[] fixpoint(int n, int[] objIndex, List<int[]> news, Set<Integer> drop, Map<Integer, List<Integer>> assignOut,
                             List<int[]> stores, List<int[]> loads) {
        Map<Integer, List<int[]>> storeBySrc = new HashMap<>();
        Map<Integer, List<int[]>> storeByBase = new HashMap<>();
        Map<Integer, List<int[]>> loadByBase = new HashMap<>();
        Map<Integer, List<int[]>> loadByField = new HashMap<>();
        for (int[] s : stores) {
            storeBySrc.computeIfAbsent(s[0], k -> new ArrayList<>()).add(new int[]{s[1], s[2]});
            storeByBase.computeIfAbsent(s[1], k -> new ArrayList<>()).add(new int[]{s[0], s[2]});
        }
        for (int[] l : loads) {
            loadByBase.computeIfAbsent(l[0], k -> new ArrayList<>()).add(new int[]{l[1], l[2]});
            loadByField.computeIfAbsent(l[2], k -> new ArrayList<>()).add(new int[]{l[0], l[1]});
        }
        BitSet[] pts = new BitSet[n];
        Map<Long, BitSet> fpts = new HashMap<>();
        ArrayDeque<Long> work = new ArrayDeque<>();
        for (int k = 0; k < news.size(); k++) {
            if (drop.contains(k)) {
                continue;
            }
            int[] e = news.get(k);
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
        return pts;
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
