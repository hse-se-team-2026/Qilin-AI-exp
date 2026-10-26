package e6prog;

/**
 * E6 hand program (docs/ai/tickets/E6-S5.md). Each object has its own class, so the facts below
 * name objects by class. Facts (from this source, independent of any analysis):
 *  F1 (calls matched): x = id(a), y = id(b): x may point to A only, y to B only.
 *  F2 (partial balance, return without a matching call): f = make(): f may point to C.
 *  F3 (context erasure at a static field): put(d) stores D in G.slot inside put, r = get() reads it
 *     inside get: r may point to D.
 *  F4 (calls and fields interleaved): one class Box, two allocation sites; the constructor
 *     stores its argument into this.v: box1 holds E, box2 holds F; e1 = box1.get() may point to
 *     E only, e2 = box2.get() to F only (a context-insensitive analysis gives both to both).
 *  F5 (callee stores into a parameter's field, caller loads): fill(h, k) does h.v = k;
 *     after fill(h, new K()), m = h.v may point to K.
 */
public class CsFacts {
    static class A { }
    static class B { }
    static class C { }
    static class D { }
    static class E { }
    static class F { }
    static class K { }

    static class Box {
        Object v;

        Box(Object v) {
            this.v = v;
        }

        Object get() {
            return this.v;
        }
    }

    static class G {
        static Object slot;
    }

    static Object id(Object o) {
        return o;
    }

    static Object make() {
        return new C();
    }

    static void put(Object o) {
        G.slot = o;
    }

    static Object get() {
        return G.slot;
    }

    static void fill(Box h, Object k) {
        h.v = k;
    }

    public static void main(String[] args) {
        Object a = new A();
        Object b = new B();
        Object x = id(a);
        Object y = id(b);
        Object f = make();
        put(new D());
        Object r = get();
        Box box1 = new Box(new E());
        Box box2 = new Box(new F());
        Object e1 = box1.get();
        Object e2 = box2.get();
        Box h = new Box(null);
        fill(h, new K());
        Object m = h.v;
        System.out.println(x.hashCode() + y.hashCode() + f.hashCode() + r.hashCode() + e1.hashCode()
                + e2.hashCode() + m.hashCode());
    }
}
