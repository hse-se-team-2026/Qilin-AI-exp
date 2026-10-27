package qilin.ucfs.idr

import qilin.CoreConfig
import qilin.core.PTA
import qilin.core.PointsToAnalysis
import qilin.core.pag.AllocNode
import qilin.core.pag.ContextField
import qilin.core.pag.FieldRefNode
import qilin.core.pag.LocalVarNode
import qilin.core.pag.Node
import qilin.core.pag.PAG
import qilin.core.pag.Parm
import qilin.core.pag.VarNode
import qilin.ucfs.LabeledEdge
import qilin.ucfs.PagEdgeKind
import qilin.ucfs.QilinPagSeam
import qilin.util.Pair as QPair
import soot.Local
import soot.RefLikeType
import soot.SootMethod
import soot.Value
import soot.jimple.AssignStmt
import soot.jimple.ClassConstant
import soot.jimple.InstanceInvokeExpr
import soot.jimple.NullConstant
import soot.jimple.Stmt
import soot.jimple.StringConstant
import soot.jimple.spark.pag.SparkField
import java.io.File

/**
 * Builds the input graph of cfl-idr-with-gll (interleaved Dyck reachability) from the global PAG of a
 * finished Qilin analysis (E6-S3; E6.md D1, D4, D5) and reads its answer back as points-to sets.
 */
object IdrExport {

    /**
     * Turns the global PAG of [pta] into a cfl-idr graph with the call edges labeled as [calls].
     * Call it after `pta.run()` or `pta.pureRun()` has returned (the PAG is read with
     * [QilinPagSeam.globalEdges]). Only [IdrCalls.ERASED] is built here; [IdrCalls.BALANCED] and
     * [IdrCalls.CS] throw `UnsupportedOperationException` (E6-S4).
     *
     * **Which PAG edges are read** (CI projection `base()` of every end, as E3 `PagExport`, E3.md D3):
     * - the `new`, `assign`, load and store edges of the global PAG; an edge with an end in a
     *   `ContextField` (`o.f`, added by the solver for the objects it found in the base's points-to
     *   set) is dropped, as in E3 D1;
     * - dropped as well: the `new` edges object -> `this` of a method (added by
     *   `CallGraphBuilder.addVirtualEdge` from the receiver's points-to set), except the edge from the
     *   ROOT object (`PTA.getRootNode()`) to `this` of the fake main, which binds the entry point and
     *   has no receiver variable; and the `new` edges into the targets of the exception records
     *   `MethodPAG.getExceptionEdges()` (catch variables, method throw nodes), which
     *   `ExceptionHandler.dispatch` added from the points-to set of the thrown variable;
     * - dropped: the `assign` edges whose CI ends are the ends of an exported call edge (below).
     *   These are the copies argument -> parameter, return -> result and callee throw node -> throw
     *   variable that `CallGraphBuilder.processCallAssign` added; the call edges replace them;
     * - kept as they are: the other `new` edges, including object -> parameter of
     *   `java.lang.ref.Finalizer.register` (`Solver.handleImplicitCallToFinalizerRegister`).
     *
     * **Call edges** (E6.md D5). For each edge of `PTA.getCallGraph()` out of a statement with an
     * invoke expression, from the caller `m` to the callee `t`, at that statement `s`:
     * - entries: argument `i` -> parameter `i` of `t` (both of reference type, the argument not
     *   `null`; the argument variable is the local, or for a string or class constant the variable
     *   `(m, constant)` of `MethodNodeFactory`); for an instance invoke into a non-static `t`, the
     *   base local of the Jimple invoke -> `this` of `t`;
     * - exits: the return node of `t` -> the variable assigned by `s` (both of reference type); with
     *   precise exceptions (`-pe`), the throw node of `t` -> the throw variable of `s`
     *   (`MethodNodeFactory.makeInvokeStmtThrowVarNode`).
     *   The nodes are looked up with `PAG.findLocalVarNode` (the node factory would add nodes and
     *   edges); an edge with an end that the PAG does not have is not exported.
     * The call graph is Spark's answer for `-pta=insens` (built on the fly from points-to sets), so
     * which methods a site calls is the analysis's; the binding of `this` by the receiver variable has
     * no dispatch filter (E3 D15, class R3): `this` of every callee of a site gets everything the base
     * local may point to.
     *
     * **Exceptions** (E6.md D5): for each record `t -> w` of `MethodPAG.getExceptionEdges()` of a
     * reachable non-phantom method (`ExceptionHandler.recordImplictEdge`: throw variable -> catch
     * variable, or -> the method throw node when no trap of the method caught the object), an
     * assignment `t -> w`. The record exists for the trap that `dispatch` chose for some object, but
     * the assignment carries every object of `t` there, without the type test of the trap (class R1).
     *
     * **Encoding** (E6.md D4, L_FT of `Sridharan2005Demand` p. 4-5): an object `o` is one vertex
     * [Layer.OBJ]; a variable `v` has two, `F(v)` (flowsTo) and `B(v)` (flowsTo-bar). `i` is the dense
     * index of the field in [IdrGraph.fields] (`ArrayElement` is one field; a static field is a
     * `GlobalVarNode` with `assign` edges):
     * - `new o -> v`: `OBJ(o) -normal-> F(v)` and `B(v) -normal-> OBJ(o)`;
     * - `assign u -> v`, and in [IdrCalls.ERASED] each call edge and exception assignment `u -> v`:
     *   `F(u) -normal-> F(v)` and `B(v) -normal-> B(u)`;
     * - store `x.f = y`: `F(y) -ob--i-> B(x)` and `F(x) -cb--ir-> B(y)`;
     * - load `z = x.f`: `F(x) -cb--i-> F(z)` and `B(z) -ob--ir-> B(x)`.
     * The answer pairs are (`OBJ(o)`, `F(v)`) ([IdrGraph.sourceVertex], [IdrGraph.answerVertex]).
     *
     * Vertex ids, field and site indices are given in the order of first occurrence; every vertex
     * lies on an edge. [IdrGraph.sites] lists the statements of the exported call edges.
     *
     * [IdrGraph.counters]: `pagEdges` (edges read from the PAG), `droppedContextField`,
     * `droppedThisNew`, `droppedExceptionNew`, `droppedCallAssign` (PAG edges, before the CI
     * projection merges any), `callEdges` (distinct CI call edges per statement and direction),
     * `callSites`, `exceptionAssigns` (distinct CI exception assignments), `vertices`, `edges`, `fields`.
     */
    @JvmStatic
    fun export(pta: PTA, calls: IdrCalls): IdrGraph {
        if (calls != IdrCalls.ERASED) {
            throw UnsupportedOperationException("IdrCalls.$calls is not exported yet (E6-S4)")
        }
        val b = Builder(calls)
        val root = pta.rootNode.base()
        val callEdges = callEdges(pta)
        val callPairs = callEdges.mapTo(HashSet()) { it.from to it.to }
        val exceptions = exceptionAssigns(pta)
        val exceptionTargets = exceptions.mapTo(HashSet()) { it.second }

        var pagEdges = 0
        var droppedContextField = 0
        var droppedThisNew = 0
        var droppedExceptionNew = 0
        var droppedCallAssign = 0
        for (e in QilinPagSeam.globalEdges(pta)) {
            pagEdges++
            if (e.from is ContextField || e.to is ContextField) {
                droppedContextField++
                continue
            }
            when (e.kind) {
                PagEdgeKind.NEW -> {
                    val o = ci(e.from) as AllocNode
                    val v = ci(e.to)
                    if (v is LocalVarNode && v.isThis && o != root) {
                        droppedThisNew++
                    } else if (v in exceptionTargets) {
                        droppedExceptionNew++
                    } else {
                        b.alloc(o, v)
                    }
                }
                PagEdgeKind.ASSIGN -> {
                    val u = ci(e.from)
                    val v = ci(e.to)
                    if ((u to v) in callPairs) {
                        droppedCallAssign++
                    } else {
                        b.assign(u, v)
                    }
                }
                PagEdgeKind.LOAD -> {
                    val fr = e.from as FieldRefNode
                    b.load(ci(fr.base), fr.field, ci(e.to))
                }
                PagEdgeKind.STORE -> {
                    val fr = e.to as FieldRefNode
                    b.store(ci(e.from), ci(fr.base), fr.field)
                }
            }
        }
        for (c in callEdges) {
            b.call(c)
        }
        for ((t, w) in exceptions) {
            b.assign(t, w)
        }
        val counters = linkedMapOf(
            "pagEdges" to pagEdges,
            "droppedContextField" to droppedContextField,
            "droppedThisNew" to droppedThisNew,
            "droppedExceptionNew" to droppedExceptionNew,
            "droppedCallAssign" to droppedCallAssign,
            "callEdges" to callEdges.size,
            "callSites" to b.sites.size,
            "exceptionAssigns" to exceptions.size,
            "vertices" to b.vertices.size,
            "edges" to b.edges.size,
            "fields" to b.fields.size,
        )
        return IdrGraph(b.edges.toList(), b.vertices, b.fields, b.sites, calls, counters)
    }

    /**
     * Points-to sets of the answer [pairs] of cfl-idr on [g]: for each pair `(u, v)` where `u` is
     * [IdrGraph.sourceVertex] of an object `o` and `v` is [IdrGraph.answerVertex] of a variable `x`,
     * `o` is in the set of `x`. Other pairs (between two variables, from or to a gadget vertex, ...)
     * are skipped. Keys are CI variables; a variable without a pair has no key.
     */
    @JvmStatic
    fun pointsTo(g: IdrGraph, pairs: Collection<Pair<Int, Int>>): Map<Node, Set<AllocNode>> {
        val out = HashMap<Node, MutableSet<AllocNode>>()
        for ((u, v) in pairs) {
            val o = g.vertices[u].node as? AllocNode ?: continue
            val x = g.vertices[v].node as? VarNode ?: continue
            if (g.sourceVertex(o) == u && g.answerVertex(x) == v) {
                out.getOrPut(x) { HashSet() }.add(o)
            }
        }
        return out
    }

    /**
     * Writes [g] in the DOT form that the CLI of cfl-idr reads (`DotParser`, as its graphs in
     * `src/main/resources`): `digraph G {`, one line `u->v[label="l"];` per edge in the order of
     * [IdrGraph.edges], `}`.
     */
    @JvmStatic
    fun writeDot(g: IdrGraph, file: File) {
        file.bufferedWriter().use { w ->
            w.write("digraph G {\n")
            for (e in g.edges) {
                w.write("${e.from}->${e.to}[label=\"${e.label}\"];\n")
            }
            w.write("}\n")
        }
    }

    /** An interprocedural edge `from -> to` at the call statement [site]: an entry (into the callee) or an exit. */
    internal data class CallEdge(val from: Node, val to: Node, val site: Stmt, val entry: Boolean)

    /** Call edges of [IdrExport.export] (see there), CI, without repeats, in the order of `PTA.getCallGraph()`. */
    internal fun callEdges(pta: PTA): List<CallEdge> {
        val pag = pta.pag
        val pe = CoreConfig.v().ptaConfig.preciseExceptions
        val out = LinkedHashSet<CallEdge>()
        fun add(from: Node?, to: Node?, s: Stmt, entry: Boolean) {
            if (from != null && to != null) {
                out.add(CallEdge(ci(from), ci(to), s, entry))
            }
        }
        for (e in pta.callGraph) {
            val s = e.srcUnit() as? Stmt ?: continue
            if (!s.containsInvokeExpr()) {
                continue
            }
            val caller = e.src()
            val callee = e.tgt()
            val ie = s.invokeExpr
            for (i in 0 until minOf(ie.argCount, callee.parameterCount)) {
                val a = ie.getArg(i)
                if (a.type is RefLikeType && a !is NullConstant && callee.getParameterType(i) is RefLikeType) {
                    add(valueNode(pag, caller, a), pag.findLocalVarNode(Parm(callee, i)), s, true)
                }
            }
            if (ie is InstanceInvokeExpr && !callee.isStatic) {
                add(valueNode(pag, caller, ie.base),
                    pag.findLocalVarNode(Parm(callee, PointsToAnalysis.THIS_NODE)), s, true)
            }
            if (s is AssignStmt && s.leftOp.type is RefLikeType && callee.returnType is RefLikeType) {
                add(pag.findLocalVarNode(Parm(callee, PointsToAnalysis.RETURN_NODE)),
                    valueNode(pag, caller, s.leftOp), s, false)
            }
            if (pe) {
                add(pag.findLocalVarNode(Parm(callee, PointsToAnalysis.THROW_NODE)), pag.findLocalVarNode(s), s, false)
            }
        }
        return out.toList()
    }

    /** The variable node of a call operand: a local, or the `(method, constant)` variable of a string/class constant. */
    private fun valueNode(pag: PAG, m: SootMethod, v: Value): Node? = when (v) {
        is Local -> pag.findLocalVarNode(v)
        is StringConstant, is ClassConstant -> pag.findLocalVarNode(QPair(m, v))
        else -> null
    }

    /** Exception assignments (throw variable, target) of [IdrExport.export], CI, without repeats. */
    internal fun exceptionAssigns(pta: PTA): List<kotlin.Pair<Node, Node>> {
        val out = LinkedHashSet<kotlin.Pair<Node, Node>>()
        for (m in pta.nakedReachableMethods) {
            if (m.isPhantom) {
                continue
            }
            for ((t, ws) in pta.pag.getMethodPAG(m).exceptionEdges) {
                ws.forEach { out.add(ci(t) to ci(it)) }
            }
        }
        return out.toList()
    }

    /** CI projection: a variable or object node becomes its `base()`. */
    private fun ci(node: Node): Node = when (node) {
        is VarNode -> node.base()
        is AllocNode -> node.base()
        else -> throw IllegalArgumentException("not a variable or object node: $node (${node.javaClass.name})")
    }

    /** Collects vertices, fields, sites and labeled edges in the order of first occurrence. */
    private class Builder(val calls: IdrCalls) {
        val vertices = ArrayList<IdrVertex>()
        private val vertexIds = HashMap<IdrVertex, Int>()
        val fields = ArrayList<SparkField>()
        private val fieldIds = HashMap<SparkField, Int>()
        val sites = ArrayList<soot.Unit>()
        private val siteIds = HashMap<soot.Unit, Int>()
        val edges = LinkedHashSet<LabeledEdge>()

        private fun id(node: Node, layer: Layer): Int {
            val v = IdrVertex(node, layer)
            return vertexIds.getOrPut(v) { vertices.add(v); vertices.size - 1 }
        }

        private fun field(f: SparkField): Int = fieldIds.getOrPut(f) { fields.add(f); fields.size - 1 }

        private fun site(s: soot.Unit): Int = siteIds.getOrPut(s) { sites.add(s); sites.size - 1 }

        private fun edge(from: Int, label: String, to: Int) {
            edges.add(LabeledEdge(from, label, to))
        }

        fun alloc(o: Node, v: Node) {
            edge(id(o, Layer.OBJ), NORMAL, id(v, Layer.F))
            edge(id(v, Layer.B), NORMAL, id(o, Layer.OBJ))
        }

        fun assign(u: Node, v: Node) {
            edge(id(u, Layer.F), NORMAL, id(v, Layer.F))
            edge(id(v, Layer.B), NORMAL, id(u, Layer.B))
        }

        /** `x.f = y`: opens the store bracket into B, and closes the reversed bracket store-bar. */
        fun store(y: Node, x: Node, f: SparkField) {
            val i = field(f)
            edge(id(y, Layer.F), "ob--$i", id(x, Layer.B))
            edge(id(x, Layer.F), "cb--${i}r", id(y, Layer.B))
        }

        /** `z = x.f`: closes the store bracket in F, and opens the reversed bracket load-bar in B. */
        fun load(x: Node, f: SparkField, z: Node) {
            val i = field(f)
            edge(id(x, Layer.F), "cb--$i", id(z, Layer.F))
            edge(id(z, Layer.B), "ob--${i}r", id(x, Layer.B))
        }

        fun call(c: CallEdge) {
            site(c.site)
            when (calls) {
                IdrCalls.ERASED -> assign(c.from, c.to)
                else -> throw UnsupportedOperationException("IdrCalls.$calls is not exported yet (E6-S4)")
            }
        }
    }

    private const val NORMAL = "normal"
}
