package qilin.test.ucfs;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;
import qilin.core.PTA;
import qilin.core.pag.AllocNode;
import qilin.core.pag.FieldRefNode;
import qilin.core.pag.MethodPAG;
import qilin.core.pag.Node;
import qilin.core.pag.ValNode;
import qilin.test.util.JunitTests;
import qilin.ucfs.PagEdgeCounts;
import qilin.ucfs.QilinPagSeam;
import soot.SootMethod;
import soot.util.queue.QueueReader;

/**
 * E2-S5 acceptance check (docs/ai/tickets/E2-S5.md): after the Qilin kernel and solver have run
 * (Spark, pta.pureRun()), Kotlin code in qilin.ucfs reads the same context-insensitive PAG as
 * Java does. The reference below walks MethodPAG internal edges of every reachable method and
 * classifies each (from, to) pair like PAG.addEdgeIntenal: AllocNode -> alloc,
 * ValNode -> ValNode = assign, ValNode -> FieldRefNode = store, FieldRefNode -> load.
 * Pairs with a null target are not counted.
 */
public class E2PagSeamTest extends JunitTests {

    private static PagEdgeCounts reference(PTA pta) {
        int methods = 0, alloc = 0, assign = 0, load = 0, store = 0;
        for (SootMethod m : pta.getNakedReachableMethods()) {
            methods++;
            MethodPAG mpag = pta.getPag().getMethodPAG(m);
            for (QueueReader<Node> r = mpag.getInternalReader().clone(); r.hasNext(); ) {
                Node from = r.next();
                Node to = r.next();
                if (to == null) {
                    continue;
                }
                if (from instanceof ValNode && to instanceof ValNode) {
                    assign++;
                } else if (from instanceof ValNode && to instanceof FieldRefNode) {
                    store++;
                } else if (from instanceof FieldRefNode) {
                    load++;
                } else if (from instanceof AllocNode) {
                    alloc++;
                }
            }
        }
        return new PagEdgeCounts(methods, alloc, assign, load, store);
    }

    private void check(String mainClass) {
        PTA pta = run(mainClass, "insens");
        PagEdgeCounts expected = reference(pta);
        assertTrue("program must have reachable methods and every edge kind: " + expected,
                expected.getMethods() > 0 && expected.getAlloc() > 0 && expected.getAssign() > 0
                        && expected.getLoad() > 0 && expected.getStore() > 0);
        System.out.println("E2PagSeamTest " + mainClass + ": " + expected);
        assertEquals(expected, QilinPagSeam.countInternalEdges(pta));
    }

    @Test
    public void instanceStore() {
        check("qilin.microben.core.field.InstanceStore");
    }

    @Test
    public void instanceLoad() {
        check("qilin.microben.core.field.InstanceLoad");
    }
}
