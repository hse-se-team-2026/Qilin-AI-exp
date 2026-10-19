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
 * - with the binding ANALYSIS `this` of A.foo holds only the A object: no new call edge.
 */
public class DispatchProg {
    static class A {
        void foo() {
            this.bar();
        }

        void bar() {
        }
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
    }
}
