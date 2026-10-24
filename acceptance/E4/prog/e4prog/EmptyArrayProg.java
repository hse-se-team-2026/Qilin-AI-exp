package e4prog;

/**
 * E4-S3 hand program with a non-zero class R5 (acceptance/E4/S3_compare.sh). Facts, read from this
 * source:
 * - {@code empty} is a zero-length array (new Object[0]); Qilin's solver never stores into or loads from
 *   an empty array (Solver.disallowStoreOrLoadOn, PTAUtils.isEmptyArray), so Spark's pts(got) is empty;
 * - the export has the store and the load on {@code empty}, and the fixpoint without that filter puts
 *   the Item object into pts(got): the pair (got, Item of main) is in UCFS and not in Spark, no declared
 *   type or cast removes it (got and the array elements are Object), so its class is R5;
 * - the non-empty array {@code full} carries a Kept object the same way, and that flow is the same in
 *   Spark and UCFS (the classes differ so that no local of main holds both objects).
 */
public class EmptyArrayProg {
    static class Item {
    }

    static class Kept {
    }

    static Object sink;

    public static void main(String[] args) {
        Object[] empty = new Object[0];
        Object[] full = new Object[1];
        if (args.length > 1000) {
            empty[0] = new Item();
        }
        full[0] = new Kept();
        Object got = null;
        if (args.length > 1000) {
            got = empty[0];
        }
        sink = got;
        sink = full[0];
    }
}
