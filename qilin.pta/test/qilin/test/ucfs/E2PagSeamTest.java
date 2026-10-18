package qilin.test.ucfs;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertTrue;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import org.junit.Test;
import qilin.core.PTA;
import qilin.core.PTAScene;
import qilin.core.pag.AllocNode;
import qilin.core.pag.ContextAllocNode;
import qilin.core.pag.ContextField;
import qilin.core.pag.ContextVarNode;
import qilin.core.pag.FieldRefNode;
import qilin.core.pag.LocalVarNode;
import qilin.core.pag.MethodPAG;
import qilin.core.pag.Node;
import qilin.core.pag.PAG;
import qilin.core.pag.ValNode;
import qilin.core.pag.VarNode;
import qilin.test.util.JunitTests;
import qilin.ucfs.PagEdge;
import qilin.ucfs.PagEdgeKind;
import qilin.ucfs.QilinPagSeam;
import soot.SootField;
import soot.SootMethod;
import soot.util.queue.QueueReader;

/**
 * E2-S5 acceptance check (docs/ai/tickets/E2-S5.md): after the Qilin kernel and solver have run
 * (Spark, pta.pureRun()), Kotlin code of qilin.ucfs exports the GLOBAL pointer assignment graph:
 * QilinPagSeam.globalEdges(pta) = every edge of the maps alloc (NEW), simple (ASSIGN), load (LOAD)
 * and store (STORE) of pta.getPag(). This is the graph E3 hands to UCFS. It holds the
 * parameterized MethodPAG edges of reachable methods AND the edges the kernel derived while
 * solving: receiver object -> this of the dispatched callee (CallGraphBuilder.addVirtualEdge),
 * argument -> parameter and return -> receiving variable (CallGraphBuilder.processCallAssign),
 * x -> o.f and o.f -> y for every object o the base may point to (Solver.handleStoreEdge /
 * handleLoadEdge, o.f = ContextField).
 *
 * <p>Oracles, none of them a copy of the implementation:
 * <ol>
 *   <li>the same edge set rebuilt through a different API: the INVERSE maps of PAG (allocInv,
 *       simpleInv, loadInv, store), enumerated through the node numberer;</li>
 *   <li>structure: every node is a context node (CorePTA.parameterize), and every MethodPAG
 *       edge of a reachable method, parameterized as Solver.addToPAG does, is in the export,
 *       which is strictly larger (derived edges exist);</li>
 *   <li>fixed facts of tiny programs of qilin.microben, derived by hand from their source (see
 *       each test).</li>
 * </ol>
 * The per-kind counts are also compared with Qilin's own counter qilin.stat.PAGStat through the
 * CLI option -ucfsseam (acceptance/E2/S5_pag_seam.sh).
 */
public class E2PagSeamTest extends JunitTests {

    private static final String CALL = "qilin.microben.core.call.VirtualCall1";

    /** Oracle 1: the global PAG read through its inverse maps, keyed by target (store: by source). */
    private static Set<PagEdge> fromInverseMaps(PAG pag) {
        Set<PagEdge> edges = new HashSet<>();
        for (ValNode v : pag.getValNodeNumberer()) {
            for (ValNode src : pag.simpleInvLookup(v)) {
                edges.add(new PagEdge(PagEdgeKind.ASSIGN, src, v));
            }
            if (v instanceof VarNode var) {
                for (AllocNode heap : pag.allocInvLookup(var)) {
                    edges.add(new PagEdge(PagEdgeKind.NEW, heap, var));
                }
                for (FieldRefNode fr : pag.loadInvLookup(var)) {
                    edges.add(new PagEdge(PagEdgeKind.LOAD, fr, var));
                }
                for (FieldRefNode fr : pag.storeLookup(var)) {
                    edges.add(new PagEdge(PagEdgeKind.STORE, var, fr));
                }
            }
        }
        return edges;
    }

    private static boolean isContextNode(Node n) {
        return n instanceof ContextVarNode || n instanceof ContextAllocNode || n instanceof ContextField
                || (n instanceof FieldRefNode fr && fr.getBase() instanceof ContextVarNode);
    }

    private static PagEdgeKind kindOf(Node from, Node to) {
        if (from instanceof AllocNode) {
            return PagEdgeKind.NEW;
        }
        if (from instanceof FieldRefNode) {
            return PagEdgeKind.LOAD;
        }
        return to instanceof FieldRefNode ? PagEdgeKind.STORE : PagEdgeKind.ASSIGN;
    }

    /**
     * Oracle 2b: the MethodPAG edges of every reachable method, parameterized with the empty
     * context (Spark insens: every method has only the empty context) as Solver.addToPAG does
     * (an allocation goes through the heap abstractor first).
     */
    private static Set<PagEdge> parameterizedInternalEdges(PTA pta) {
        Set<PagEdge> edges = new HashSet<>();
        for (SootMethod m : pta.getNakedReachableMethods()) {
            if (m.isPhantom()) {
                continue;
            }
            MethodPAG mpag = pta.getPag().getMethodPAG(m);
            for (QueueReader<Node> r = mpag.getInternalReader().clone(); r.hasNext(); ) {
                Node from = r.next();
                Node to = r.next();
                if (from instanceof AllocNode heap) {
                    from = pta.heapAbstractor().abstractHeap(heap);
                }
                from = pta.parameterize(from, pta.emptyContext());
                to = pta.parameterize(to, pta.emptyContext());
                edges.add(new PagEdge(kindOf(from, to), from, to));
            }
        }
        return edges;
    }

    private static long count(Set<PagEdge> edges, PagEdgeKind kind) {
        return edges.stream().filter(e -> e.getKind() == kind).count();
    }

    /** Runs Spark on mainClass and checks the oracles valid for every program. */
    private Set<PagEdge> exportAndCheck(String mainClass) {
        PTA pta = run(mainClass, "insens");
        Set<PagEdge> global = QilinPagSeam.globalEdges(pta);
        System.out.println("E2PagSeamTest " + mainClass + ": NEW=" + count(global, PagEdgeKind.NEW)
                + " ASSIGN=" + count(global, PagEdgeKind.ASSIGN) + " LOAD=" + count(global, PagEdgeKind.LOAD)
                + " STORE=" + count(global, PagEdgeKind.STORE));
        assertTrue("program must have NEW and ASSIGN edges", count(global, PagEdgeKind.NEW) > 0
                && count(global, PagEdgeKind.ASSIGN) > 0);

        assertEquals("globalEdges must equal the global PAG read through its inverse maps",
                fromInverseMaps(pta.getPag()), global);

        for (PagEdge e : global) {
            assertEquals("kind must follow the node types (PAG.addEdge): " + e, kindOf(e.getFrom(), e.getTo()), e.getKind());
            assertTrue("global PAG nodes are context nodes: " + e, isContextNode(e.getFrom()) && isContextNode(e.getTo()));
        }

        Set<PagEdge> internal = parameterizedInternalEdges(pta);
        Set<PagEdge> notExported = new HashSet<>(internal);
        notExported.removeAll(global);
        assertTrue("every parameterized MethodPAG edge must be exported, missing: " + notExported, notExported.isEmpty());
        assertTrue("the export must also hold edges derived by the solver", global.size() > internal.size());
        return global;
    }

    private static SootMethod method(String signature) {
        return PTAScene.v().getMethod(signature);
    }

    private static boolean isLocalOf(Node n, SootMethod m) {
        return n instanceof ContextVarNode cv && cv.base() instanceof LocalVarNode lv && lv.getMethod().equals(m);
    }

    private static boolean isFieldOfObjectOfType(Node n, String fieldName, String type) {
        return n instanceof ContextField cf && cf.hasBase() && cf.getField() instanceof SootField f
                && f.getName().equals(fieldName) && cf.getBase().getType().toString().equals(type);
    }

    /**
     * VirtualCall1: {@code A1 a1 = new A2(); A1 a2 = new A2(); a1.foo(a2);} where A2 inherits
     * A1.foo(Object p). Dispatch of {@code a1.foo} adds exactly one NEW edge into {@code this} of
     * A1.foo, from the object of a1 (the first {@code new A2()}); passing a2 adds exactly one
     * ASSIGN edge from a local of main into p. Neither edge is a MethodPAG edge (they cross
     * methods), and the object reaching {@code this} is not the one reaching p
     * (Assert.notAlias(this, p) in the source).
     */
    @Test
    public void virtualCall1() {
        Set<PagEdge> global = exportAndCheck(CALL);
        SootMethod main = method("<" + CALL + ": void main(java.lang.String[])>");
        SootMethod foo = method("<" + CALL + "$A1: void foo(java.lang.Object)>");

        List<PagEdge> intoThis = global.stream()
                .filter(e -> e.getKind() == PagEdgeKind.NEW && e.getTo() instanceof ContextVarNode cv
                        && cv.base() instanceof LocalVarNode lv && lv.getMethod().equals(foo) && lv.isThis())
                .collect(Collectors.toList());
        assertEquals("one NEW edge into this of A1.foo (dispatch of a1.foo): " + intoThis, 1, intoThis.size());
        AllocNode receiver = ((ContextAllocNode) intoThis.get(0).getFrom()).base();
        assertEquals(CALL + "$A2", receiver.getType().toString());
        assertEquals(main, receiver.getMethod());

        Node thisOfFoo = intoThis.get(0).getTo();
        List<PagEdge> intoParam = global.stream()
                .filter(e -> e.getKind() == PagEdgeKind.ASSIGN && e.getTo() instanceof ContextVarNode cv
                        && cv.base() instanceof LocalVarNode lv && lv.getMethod().equals(foo) && !lv.isThis()
                        && isLocalOf(e.getFrom(), main))
                .collect(Collectors.toList());
        assertEquals("one ASSIGN edge from main into a parameter of A1.foo (argument a2): " + intoParam, 1, intoParam.size());
        Node param = intoParam.get(0).getTo();
        assertNotEquals(thisOfFoo, param);

        // the objects reaching p: sources of NEW edges into the argument variable in main
        Node arg = intoParam.get(0).getFrom();
        Set<Node> argObjects = global.stream()
                .filter(e -> e.getKind() == PagEdgeKind.NEW && e.getTo().equals(arg))
                .map(PagEdge::getFrom).collect(Collectors.toSet());
        assertEquals("the argument a2 holds exactly its own new A2(): " + argObjects, 1, argObjects.size());
        assertFalse("this and p of A1.foo must not get the same object", argObjects.contains(intoThis.get(0).getFrom()));
    }

    /**
     * InstanceStore: {@code i = new InstanceStore(); o = new Object(); i.a = o;}. The STORE edge
     * o -> i.a is a MethodPAG edge; because i points to the InstanceStore object, the solver adds
     * the ASSIGN edge o -> (that object).a, a ContextField. No MethodPAG edge touches a
     * ContextField, so such edges exist only in the global PAG.
     */
    @Test
    public void instanceStore() {
        Set<PagEdge> global = exportAndCheck("qilin.microben.core.field.InstanceStore");
        SootMethod main = method("<qilin.microben.core.field.InstanceStore: void main(java.lang.String[])>");
        assertTrue("STORE edge from a local of main into i.a", global.stream().anyMatch(e -> e.getKind() == PagEdgeKind.STORE
                && isLocalOf(e.getFrom(), main)));
        assertTrue("ASSIGN edge local of main -> o.a of the InstanceStore object", global.stream().anyMatch(e ->
                e.getKind() == PagEdgeKind.ASSIGN && isLocalOf(e.getFrom(), main)
                        && isFieldOfObjectOfType(e.getTo(), "a", "qilin.microben.core.field.InstanceStore")));
    }

    /**
     * InstanceLoad: field initializer {@code a = new Object()} runs in the constructor
     * ({@code this.a = new Object()}), and main reads {@code o.a}. The solver adds the ASSIGN edge
     * (local of the constructor) -> o.a and the ASSIGN edge o.a -> (local of main), o being the
     * InstanceLoad object.
     */
    @Test
    public void instanceLoad() {
        Set<PagEdge> global = exportAndCheck("qilin.microben.core.field.InstanceLoad");
        String cls = "qilin.microben.core.field.InstanceLoad";
        SootMethod main = method("<" + cls + ": void main(java.lang.String[])>");
        SootMethod init = method("<" + cls + ": void <init>()>");
        assertTrue("ASSIGN edge o.a -> local of main", global.stream().anyMatch(e -> e.getKind() == PagEdgeKind.ASSIGN
                && isFieldOfObjectOfType(e.getFrom(), "a", cls) && isLocalOf(e.getTo(), main)));
        assertTrue("ASSIGN edge local of the constructor -> o.a", global.stream().anyMatch(e -> e.getKind() == PagEdgeKind.ASSIGN
                && isLocalOf(e.getFrom(), init) && isFieldOfObjectOfType(e.getTo(), "a", cls)));
        assertTrue("LOAD edge o.a (FieldRefNode) -> local of main", global.stream().anyMatch(e -> e.getKind() == PagEdgeKind.LOAD
                && isLocalOf(e.getTo(), main)));
    }
}
