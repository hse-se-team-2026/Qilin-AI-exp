package qilin.ucfs.idr

import qilin.core.pag.AllocNode
import qilin.core.pag.ArrayElement
import qilin.core.pag.GlobalVarNode
import qilin.core.pag.LocalVarNode
import qilin.core.pag.MergedNewExpr
import qilin.core.pag.Node
import qilin.core.pag.Parm
import qilin.util.PTAUtils
import soot.Local
import soot.SootField
import soot.SootMethod
import soot.jimple.spark.pag.SparkField
import java.util.IdentityHashMap

/**
 * Keys of the CI nodes, fields and call statements of an export that are the same in every run of the
 * JVM on the same input (E6-S4b), so that [IdrExport.export] can order what it reads from the PAG.
 *
 * The node numbers of Qilin (`Node.getNumber()`, also its `hashCode`) are given in the order the solver
 * creates the nodes, and that order follows maps keyed by objects with an identity hash (`SootMethod`,
 * ...); `MergedNewExpr` prints its identity hash. So neither the order of the PAG maps nor `toString()`
 * of a node is stable between runs. A key is built from what is: the signature of the method, the
 * position of a Jimple local or statement in the body of that method (`PTAUtils.getMethodBody`, the body
 * the PAG was built from), the index of a parameter, the signature of a field, the text of a constant,
 * the type of a merged object. [node] keys of two distinct nodes coincide only where that is not enough
 * (e.g. two allocation expressions that are in no statement of the body, as the inner arrays of a
 * `newmultiarray`); [ties] counts them.
 */
internal class StableKeys {
    private val nodeKeys = HashMap<Node, String>()
    private val fieldKeys = HashMap<SparkField, String>()
    private val siteKeys = HashMap<soot.Unit, String>()
    private val places = HashMap<SootMethod, IdentityHashMap<Any, String>>()

    /** The signature of [m]; `-` for none. */
    fun method(m: SootMethod?): String = m?.signature ?: "-"

    /**
     * Key of a CI node: `o <method> <allocation> : <type>` for an object (the allocation is its place in
     * the body, `merged` for a `MergedNewExpr`, the text of a constant or a string such as `ROOT`),
     * `l <method> <variable> : <type>` for a local variable (a place in the body, `parm <i>`, the pair of
     * a constant), `g <variable> : <type>` for a global one (a field signature, a constant).
     */
    fun node(n: Node): String = nodeKeys.getOrPut(n) {
        when (n) {
            is AllocNode -> "o ${method(n.method)} ${allocation(n)} : ${n.type}"
            is LocalVarNode -> "l ${method(n.method)} ${variable(n.variable, n.method)} : ${n.type}"
            is GlobalVarNode -> "g ${global(n.variable)} : ${n.type}"
            else -> "n ${n.javaClass.name} ${plain(n)} : ${n.type}"
        }
    }

    /** Key of a field: its signature, `[]` for the array element. */
    fun field(f: SparkField): String = fieldKeys.getOrPut(f) {
        when (f) {
            is SootField -> f.signature
            is ArrayElement -> "[]"
            else -> "${f.javaClass.name} ${plain(f)}"
        }
    }

    /** Key of the call statement [s] of [caller]: the method and the position of [s] in its body. */
    fun site(caller: SootMethod, s: soot.Unit): String =
        siteKeys.getOrPut(s) { "${method(caller)} ${place(caller, s) ?: plain(s)}" }

    /** Number of [nodes] whose key is the key of another of them. */
    fun ties(nodes: Collection<Node>): Int =
        nodes.toSet().groupingBy { node(it) }.eachCount().values.filter { it > 1 }.sum()

    private fun allocation(o: AllocNode): String = when (val e = o.newExpr) {
        is MergedNewExpr -> "merged"
        is String -> "\"$e\""
        else -> place(o.method, e) ?: plain(e)
    }

    private fun variable(v: Any, m: SootMethod?): String = when (v) {
        is Parm -> "parm ${v.index}"
        is Local -> place(m, v) ?: "local ${v.name}"
        else -> place(m, v) ?: plain(v)
    }

    private fun global(v: Any): String = when (v) {
        is SootField -> v.signature
        else -> plain(v)
    }

    /**
     * `local <i> <name>` for the local `i` of the body of [m], `unit <i>` for statement `i` of the body,
     * `unit <i> <class>` for a value in one of its boxes (the first such statement); null if [x] is not
     * there.
     */
    private fun place(m: SootMethod?, x: Any): String? {
        if (m == null) {
            return null
        }
        val map = places.getOrPut(m) {
            val out = IdentityHashMap<Any, String>()
            val body = PTAUtils.getMethodBody(m)
            body.locals.forEachIndexed { i, l -> out.putIfAbsent(l, "local $i ${l.name}") }
            body.units.forEachIndexed { i, u ->
                out.putIfAbsent(u, "unit $i")
                u.useAndDefBoxes.forEach { out.putIfAbsent(it.value, "unit $i ${it.value.javaClass.simpleName}") }
            }
            out
        }
        return map[x]
    }

    /** `toString()` without identity hash codes (`@1b2c3d4`) and runs of white space. */
    private fun plain(x: Any): String = x.toString().replace(HASH, "@").replace(SPACE, " ")

    private companion object {
        val HASH = Regex("@[0-9a-f]{4,8}\\b")
        val SPACE = Regex("\\s+")
    }
}
