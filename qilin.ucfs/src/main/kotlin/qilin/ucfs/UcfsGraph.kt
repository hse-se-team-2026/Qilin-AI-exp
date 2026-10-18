package qilin.ucfs

import qilin.core.pag.AllocNode
import qilin.core.pag.Node
import soot.jimple.spark.pag.SparkField

/**
 * Labeled input graph for UCFS over dense vertex ids, made by [PagExport.export].
 *
 * Vertex `i` (`0 <= i < vertices.size`) is the context-insensitive PAG node `vertices[i]`; field
 * index `i` (`0 <= i < fields.size`) is the field `fields[i]` used in the labels
 * [PtLabels.store] and [PtLabels.load]. The constructor rejects lists with repeated nodes or
 * fields and edges whose ends are not vertex ids.
 *
 * @property edges forward and reversed edges ([PtLabels.bar]); [PagExport] adds no edge twice
 * @property vertices vertex id -> node; in a graph from [PagExport] a CI node (`LocalVarNode`,
 *   `GlobalVarNode` or `AllocNode`, not a context node)
 * @property fields field index -> instance field or `ArrayElement`
 */
class UcfsGraph(
    edges: List<LabeledEdge>,
    vertices: List<Node>,
    fields: List<SparkField>,
) {
    val edges: List<LabeledEdge> = java.util.Collections.unmodifiableList(ArrayList(edges))
    val vertices: List<Node> = java.util.Collections.unmodifiableList(ArrayList(vertices))
    val fields: List<SparkField> = java.util.Collections.unmodifiableList(ArrayList(fields))

    private val vertexIds: Map<Node, Int> = indexOf(this.vertices, "vertex")
    private val fieldIds: Map<SparkField, Int> = indexOf(this.fields, "field")

    init {
        val n = this.vertices.size
        for (e in this.edges) {
            require(e.from in 0 until n && e.to in 0 until n) { "edge end is not a vertex id (n=$n): $e" }
        }
    }

    /**
     * Id of [node], or -1 if [node] is not a vertex. The lookup does not project: in a graph from
     * [PagExport] a context node (`ContextVarNode`, `ContextAllocNode`) gives -1, so project it
     * with `base()` first.
     */
    fun vertexOf(node: Node): Int = vertexIds[node] ?: -1

    /** The node of vertex [id]; throws `IndexOutOfBoundsException` for an id outside `0 until vertices.size`. */
    fun nodeOf(id: Int): Node = vertices[id]

    /**
     * Dense index of [field] in the labels `store_i`/`load_i`, or -1 if [field] is not in [fields]
     * (in a graph from [PagExport]: if no exported load or store edge uses it).
     */
    fun fieldIndex(field: SparkField): Int = fieldIds[field] ?: -1

    /** Ids of the vertices that are objects (`AllocNode`), in increasing order. */
    fun allocVertices(): List<Int> = vertices.indices.filter { vertices[it] is AllocNode }

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
