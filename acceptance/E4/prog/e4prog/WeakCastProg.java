package e4prog;

/**
 * E4-S3b hand program: a cast whose type object is not the Scene's {@code java.lang.Object}
 * (acceptance/E4/S3b_weak_type.sh). Facts, read from this source and from Soot's typing of it:
 * - in {@code twoArrays} one local of type {@code Object} gets a {@code char[]} or an {@code Object[]};
 *   Soot splits it and casts each array to {@code java.lang.Object} with a {@code WeakObjectType}, a
 *   type that equals the Scene's {@code Object} but is another object (acceptance/E4/WeakTypeProbe.java
 *   prints it); {@code FastHierarchy.canStoreType} compares the supertype of an array type with the
 *   Scene's {@code Object} by {@code ==}, so Qilin's solver keeps neither array in the cast nodes:
 *   Spark's pts of the cast nodes are empty, and no array made in {@code twoArrays} reaches its return
 *   or {@code weak} (the argument {@code new char[1]} does, through the parameter);
 * - without filters (UCFS) both arrays flow through the casts to {@code weak}; no declared type removes
 *   them (every variable on the way is {@code Object}), the cast type does: their class is R2;
 * - control: {@code oneArray} returns a {@code char[]} through the canonical {@code Object} return type
 *   to {@code canonical}, without a cast; Spark keeps it there (the pair is SAME);
 * - the two flows are in different methods, so that no local of one method holds both.
 */
public class WeakCastProg {
    static Object weak;
    static Object canonical;

    static Object twoArrays(Object array, int n) {
        Object newArray;
        if (array instanceof char[]) {
            newArray = new char[n];
        } else {
            newArray = new Object[n];
        }
        return newArray;
    }

    static Object oneArray(int n) {
        Object newArray = new char[n];
        return newArray;
    }

    static void useWeak(int n) {
        weak = twoArrays(new char[1], n);
    }

    static void useCanonical(int n) {
        canonical = oneArray(n);
    }

    public static void main(String[] args) {
        useWeak(args.length);
        useCanonical(args.length);
    }
}
