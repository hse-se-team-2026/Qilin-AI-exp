import driver.Main;
import qilin.core.PTA;
import qilin.core.pag.GlobalVarNode;
import qilin.core.pag.LocalVarNode;
import qilin.core.pag.ValNode;
import soot.RefType;
import soot.Scene;
import soot.SootField;
import soot.Type;
import soot.jimple.CastExpr;

import java.util.Arrays;
import java.util.TreeSet;

/**
 * E4-S3b acceptance probe (acceptance/E4/S3b_weak_type.sh; docs/ai/tickets/E4-S3b.md): runs
 * driver.Main.run with the given Qilin arguments and prints, for each variable node of a class whose
 * name starts with the first argument and whose type is named java.lang.Object, one line
 * "WEAKTYPE <cast|var>\t<node>\t<Java class of the type object>\t<scene|other>", sorted, no line twice:
 * "scene" when the type object is Scene.v().getObjectType() - the object FastHierarchy.canStoreType
 * compares the supertype of an array type with by == - and "other" when it is another object.
 * It reads only Soot and the PAG of the run, nothing of qilin.pta.ucfs.
 * Usage: java -cp <Qilin fat jar> acceptance/E4/WeakTypeProbe.java <class prefix> <qilin args...>
 */
public class WeakTypeProbe {
    public static void main(String[] args) {
        String prefix = args[0];
        PTA pta = Main.run(Arrays.copyOfRange(args, 1, args.length));
        Type object = Scene.v().getObjectType();
        TreeSet<String> lines = new TreeSet<>();
        for (ValNode n : pta.getPag().getValNodes()) {
            String owner;
            boolean cast = false;
            if (n instanceof LocalVarNode lv) {
                owner = lv.getMethod().getDeclaringClass().getName();
                cast = lv.getVariable() instanceof CastExpr;
            } else if (n instanceof GlobalVarNode gv && gv.getVariable() instanceof SootField f) {
                owner = f.getDeclaringClass().getName();
            } else {
                continue;
            }
            Type t = n.getType();
            if (owner.startsWith(prefix) && t instanceof RefType rt && rt.getClassName().equals("java.lang.Object")) {
                lines.add("WEAKTYPE " + (cast ? "cast" : "var") + "\t" + n + "\t" + t.getClass().getName() + "\t"
                        + (t == object ? "scene" : "other"));
            }
        }
        lines.forEach(System.out::println);
    }
}
