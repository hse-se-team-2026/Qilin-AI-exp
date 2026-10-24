package e4prog;

/**
 * E4-S4 hand program (acceptance/E4/S4_dispatch.sh). Facts, read from this source:
 * - call(x) is called with an A and with a B object, so Spark's pts(x) = {A, B} and x.foo() calls
 *   A.foo (for the A object) and B.foo (for the B object); B overrides foo, so only the A object
 *   reaches `this` of A.foo, and this.bar() in A.foo calls only A.bar in Spark's call graph;
 * - with the receiver binding CALL_GRAPH the edge x -assign-> this(A.foo) carries both objects, so the
 *   UCFS answer has the pair (this of A.foo, the B object) (class R3) and dispatching this.bar() in
 *   A.foo over it finds B.bar: exactly one call edge that Spark's call graph does not have, in the
 *   views UCFS and UCFS_TYPED (B is a subtype of A), none in the view SPARK;
 * - with the binding ANALYSIS `this` of A.foo holds only the A object: no new call edge;
 * - special invoke (both bindings): A.viaOther(other) calls the private method other.priv(), which
 *   javac --release 8 compiles to invokespecial. Its only actual argument is (A) o in special(), o a C object,
 *   C unrelated to A: Spark's cast filter keeps pts(other) empty, so Spark's call graph has no edge at
 *   that site; the UCFS answer (no cast filter) has the pair (other, C). Dispatch of a special invoke
 *   resolves to A.priv whatever the object, and the solver keeps the target only when the object's
 *   type can be stored in the target's class (CallGraphBuilder.dispatch, canStoreType): C cannot, so
 *   no view has a call edge to A.priv. A dispatch without that check would report one in UCFS.
 */
public class DispatchProg {
    static class A {
        void foo() {
            this.bar();
        }

        void bar() {
        }

        private void priv() {
        }

        static void viaOther(A other) {
            other.priv();
        }
    }

    static class C {
    }

    static class B extends A {
        void foo() {
        }

        void bar() {
        }
    }

    static void call(A x) {
        x.foo();
    }

    public static void main(String[] args) {
        call(new A());
        call(new B());
        special(args.length > 1000);
    }

    static void special(boolean never) {
        Object o = new C();
        if (never) {
            A.viaOther((A) o);
        }
    }
}
