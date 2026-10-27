package qilin.ucfs.idr

import qilin.core.pag.AllocNode
import qilin.core.pag.Node
import qilin.core.pag.VarNode
import qilin.ucfs.LabeledEdge
import soot.jimple.spark.pag.SparkField
import soot.Unit as SootUnit

/**
 * How [IdrExport.export] labels the interprocedural edges (argument -> parameter, receiver -> `this`,
 * return -> result, callee throw node -> throw variable of the call statement) (E6.md D4-D6).
 */
enum class IdrCalls {
    /**
     * Call edges are `normal`; fields are brackets of one family (`ob--i`/`cb--i`, `ob--ir`/`cb--ir`).
     * The language is then a plain Dyck language over the field brackets (L_FT of
     * `Sridharan2005Demand`), so cfl-idr's under- and over-approximation coincide (E6.md D4, D7 (a)).
     */
    ERASED,

    /**
     * Call edges as parentheses `op--c`/`cp--c` per call site, without gadgets: cfl-idr's own semantics,
     * where both bracket families are fully balanced (E6.md D6). For points-to it loses the pairs whose
     * path returns from a method it did not enter (factories, constructors) or ends inside a callee;
     * a diagnostic mode (E6-S4).
     */
    BALANCED,

    /**
     * Call parentheses per call site with the START/END and context-erasure gadgets: the language
     * L_F ∩ R_C of `Sridharan2006Refinement` (partially balanced calls, the stack erased at the
     * context-insensitive variables) reduced to the fully balanced IDR that cfl-idr solves
     * (E6.md D6; E6-S4; details in [IdrExport.export]).
     */
    CS,
}

/**
 * Layer of a vertex of the IDR graph (E6.md D4, D6).
 *
 * [OBJ] is an object; [F] and [B] are the two phases of a variable in L_FT (flowsTo and the
 * reversed flowsTo-bar). [START], [END], [F_IN] and [B_IN] are the gadget vertices of [IdrCalls.CS]
 * (E6-S4): where the paths of an object start, where the paths to a variable end, and where the edges
 * into a context-insensitive variable enter (F and B layer); the [IdrCalls.ERASED] and
 * [IdrCalls.BALANCED] exports have only [OBJ], [F] and [B].
 */
enum class Layer { OBJ, F, B, START, END, F_IN, B_IN }

/** A vertex of the IDR graph: a CI PAG node (`AllocNode`, `LocalVarNode`, `GlobalVarNode`) in one [layer]. */
data class IdrVertex(val node: Node, val layer: Layer)

/**
 * Labeled graph for cfl-idr-with-gll over dense vertex ids, made by [IdrExport.export].
 *
 * Vertex `i` (`0 <= i < vertices.size`) is `vertices[i]`; field index `i` (`0 <= i < fields.size`) is
 * the field `fields[i]` of the labels `ob--i`, `cb--i`, `ob--ir`, `cb--ir`; site index `c` is the call
 * statement `sites[c]` of the labels `op--c`/`cp--c` (in [IdrCalls.ERASED] no label uses it, the list
 * holds the call statements of the exported call edges all the same). The constructor rejects
 * repeated vertices, fields, sites or edges and edges whose ends are not vertex ids.
 *
 * @property edges labeled edges in the format of cfl-idr (`normal`, `ob--i`, ...), without repeats
 * @property vertices vertex id -> vertex, without repeats
 * @property fields field index -> instance field or `ArrayElement`
 * @property sites site index -> call statement
 * @property calls how the call edges are labeled
 * @property counters sizes of the export and the number of PAG edges dropped or replaced per reason
 *   (keys in [IdrExport.export])
 */
class IdrGraph(
    edges: List<LabeledEdge>,
    vertices: List<IdrVertex>,
    fields: List<SparkField>,
    sites: List<SootUnit>,
    val calls: IdrCalls,
    counters: Map<String, Int>,
) {
    val edges: List<LabeledEdge> = java.util.Collections.unmodifiableList(ArrayList(edges))
    val vertices: List<IdrVertex> = java.util.Collections.unmodifiableList(ArrayList(vertices))
    val fields: List<SparkField> = java.util.Collections.unmodifiableList(ArrayList(fields))
    val sites: List<SootUnit> = java.util.Collections.unmodifiableList(ArrayList(sites))
    val counters: Map<String, Int> = java.util.Collections.unmodifiableMap(LinkedHashMap(counters))

    private val vertexIds: Map<IdrVertex, Int> = indexOf(this.vertices, "vertex")

    init {
        indexOf(this.fields, "field")
        indexOf(this.sites, "site")
        indexOf(this.edges, "edge")
        val n = this.vertices.size
        for (e in this.edges) {
            require(e.from in 0 until n && e.to in 0 until n) { "edge end is not a vertex id (n=$n): $e" }
        }
    }

    /** Id of [v], or -1 if [v] is not a vertex. The node is not projected: a context node gives -1. */
    fun idOf(v: IdrVertex): Int = vertexIds[v] ?: -1

    /**
     * The vertex where the paths of object [o] start: [Layer.OBJ] in [IdrCalls.ERASED] and
     * [IdrCalls.BALANCED], [Layer.START] in [IdrCalls.CS]; -1 if the export has no such vertex.
     * [o] is projected with `base()`.
     */
    fun sourceVertex(o: AllocNode): Int =
        idOf(IdrVertex(o.base(), if (calls == IdrCalls.CS) Layer.START else Layer.OBJ))

    /**
     * The vertex where the paths to variable [v] end: [Layer.F] in [IdrCalls.ERASED] and
     * [IdrCalls.BALANCED]; in [IdrCalls.CS] [Layer.END], and [Layer.F_IN] for a context-insensitive
     * variable (no END vertex); -1 if the export has no such vertex. [v] is projected with `base()`.
     */
    fun answerVertex(v: VarNode): Int {
        val ci = v.base()
        if (calls != IdrCalls.CS) {
            return idOf(IdrVertex(ci, Layer.F))
        }
        val end = idOf(IdrVertex(ci, Layer.END))
        return if (end >= 0) end else idOf(IdrVertex(ci, Layer.F_IN))
    }

    private companion object {
        fun <T : Any> indexOf(list: List<T>, what: String): Map<T, Int> {
            val ids = HashMap<T, Int>(list.size * 2)
            list.forEachIndexed { i, x ->
                val old = ids.put(x, i)
                require(old == null) { "$what $x occurs twice (ids $old and $i)" }
            }
            return ids
        }
    }
}
