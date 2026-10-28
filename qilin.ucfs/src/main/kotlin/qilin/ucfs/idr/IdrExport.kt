package qilin.ucfs.idr

import qilin.CoreConfig
import qilin.core.PTA
import qilin.core.PointsToAnalysis
import qilin.core.pag.AllocNode
import qilin.core.pag.ContextField
import qilin.core.pag.FieldRefNode
import qilin.core.pag.GlobalVarNode
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
import java.util.BitSet

/**
 * Builds the input graph of cfl-idr-with-gll (interleaved Dyck reachability) from the global PAG of a
 * finished Qilin analysis (E6-S3; E6.md D1, D4, D5) and reads its answer back as points-to sets.
 */
object IdrExport {

    /**
     * Turns the global PAG of [pta] into a cfl-idr graph with the call edges labeled as [calls].
     * Call it after `pta.run()` or `pta.pureRun()` has returned (the PAG is read with
     * [QilinPagSeam.globalEdges]).
     *
     * **Boundary (E6.md "Цель", D5).** The call graph (`PTA.getCallGraph()`) and the exception records
     * (`MethodPAG.getExceptionEdges()`) are Spark's answer for the run that built the PAG (`-pta=insens`):
     * which methods a site calls, and which trap or method throw node an exception reaches, come from
     * Spark's points-to sets, in every mode. The export does not re-derive them; cfl-idr answers on that
     * graph. So the answer of cfl-idr is another analysis on Spark's call graph, not one that is more or
     * less precise than Spark by construction (comparison with Spark and k-CFA: E7).
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
     *   `java.lang.ref.Finalizer.register` (`Solver.handleImplicitCallToFinalizerRegister`) and
     *   object -> static field (`PAG.addGlobalPAGEdge`).
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
     *
     * **Call parentheses** ([IdrCalls.BALANCED], [IdrCalls.CS]; E6.md D6, callEntry = param | return-bar,
     * callExit = return | param-bar of R_C in `Sridharan2006Refinement` p. 9-10). `c` is the index of the
     * call statement in [IdrGraph.sites]:
     * - entry `a -> p` at `c`: `F(a) -op--c-> F(p)` and `B(p) -cp--c-> B(a)`;
     * - exit `r -> d` at `c`: `F(r) -cp--c-> F(d)` and `B(d) -op--c-> B(r)`.
     * Exception assignments stay `normal` (they do not leave a method). [IdrCalls.BALANCED] is this and
     * nothing else: cfl-idr's own semantics, both bracket families fully balanced (E6.md D1).
     *
     * **Gadgets of [IdrCalls.CS]** (E6.md D6). The language is L_F ∩ R_C of `Sridharan2006Refinement`
     * (p. 9-11): the call parentheses are partially balanced (returns with no matching call first,
     * calls never returned from last; the stack is kept on the objects, which gives a context-sensitive
     * heap), and the stack is erased at the context-insensitive variables (assignglobal erases it,
     * p. 11). cfl-idr only solves the fully balanced language and drops unmatched labels (E6.md D1), so
     * partial balance and erasure are encoded with extra vertices and self-loops:
     * - START: for each object `o`, `START(o) -normal-> OBJ(o)` and a loop `op--c` on `START(o)` per
     *   site `c` of `sites(M(o))` (below); a path from `START(o)` opens there the parentheses that it
     *   later closes by returns without a matching call;
     * - END: for each variable `v` that is not context-insensitive, `F(v) -normal-> END(v)` and a loop
     *   `cp--c` on `END(v)` per site of `sites({method of v})`; a path to `END(v)` closes there the calls
     *   it never returned from;
     * - erasure: the context-insensitive variables X are every `GlobalVarNode` (static fields, the
     *   variables of string and class constants), every target of a cross-method `new` of the kernel
     *   (an object of method `m` into a local variable of another method; the edges into `this` and
     *   into exception targets are not exported, ROOT and objects without a method do not count;
     *   `Solver.handleImplicitCallToFinalizerRegister` adds such edges), and every local target of an
     *   object without a method outside the home method of that object ([homes]: the method with most
     *   of its local targets). The last are the merged heap of `-mh` (`HeuristicAbstractor.abstractHeap`
     *   merges every `StringBuilder`/`StringBuffer` and each `Throwable` type into one `MergedNewExpr`
     *   object with no method, and `Solver.addToPAG` adds its `new` edges into the locals of every
     *   method that allocated one); they are the cross-method `new` of an object whose method is its
     *   home (ticket E6-S4, Verifier MAJOR-V1, iteration 1). An exported edge that would
     *   end in `F(X)` or `B(X)` ends in `F_IN(X)` or `B_IN(X)` instead (the edges out of X leave `F(X)`
     *   and `B(X)`); `F_IN(X) -normal-> F(X)` and `B_IN(X) -normal-> B(X)`; loops `cp--c` on `F_IN(X)`
     *   and `B_IN(X)` close whatever the path had on its stack, loops `op--c` on `F(X)` and `B(X)` open
     *   what it closes later by unmatched returns. All four loop sets are `sites(M(X))`. The answer of X
     *   is `F_IN(X)` (it has no END).
     *
     * **Which sites loop** (docs/ai/tickets/E6-S4.md, DoD; E6.md D6 and "Решение лида" of round 2, item 1). `sites(M)` are the
     * call sites `c` (exported, i.e. in [IdrGraph.sites]) one of whose callees reaches a method of `M` in
     * the call graph (`PTA.getCallGraph()`, transitively, a method reaches itself); `M` without a method
     * (null) gives every site. Cut a path of the language at its context-insensitive vertices (and at
     * START, END) into segments. Between two of them the method of the path changes only along call
     * edges: an assignment, load or store connects two variables of one method (a global is X), and
     * `B(v) -> OBJ(o) -> F(w)` with `v`, `w` not X stays in one method, because the local targets of `o`
     * that are not X all lie in the method of `o`, or in its home if `o` has no method (the targets in
     * other methods are X, see erasure above). Without that, a path through an object without a method
     * (the merged heap) went from the method of `v` to the one of `w` with the stack of the first: a
     * parenthesis of a site that reaches only the method of `v` stayed open in `w`, and no loop by the
     * method of `w` closed it (MAJOR-V1: pairs of `E6Reference.CsModel` lost). Within a segment, the
     * parentheses it closes with no matching open are sites whose callee reaches the method where the
     * segment starts, and those it leaves open are sites whose callee reaches the method where it ends
     * (each unmatched return leaves the callee of its site for a caller; each unmatched call enters the
     * callee). The loops at the two ends of the segment (the sets below) contain those, and erasing more
     * than `CsModel` does only adds paths. For other cross-method edges see below. Hence:
     * - `M(o)` of an object is its method; for an object without a method (the merged heap, string and
     *   class constants, ROOT) it is the set of methods of its local targets that are not
     *   context-insensitive (the path from `START(o)` or from `B(v)` through `OBJ(o)` goes on to `F` of
     *   a target; that is its home method, or nothing when all its targets are X), and a target
     *   without a method gives null;
     * - `M(X)` of a context-insensitive variable is the union over every exported edge incident to X
     *   (assignments, call edges, exception assignments, `new` edges - including the cross-method
     *   object -> X and the `new` into a `GlobalVarNode` of `addGlobalPAGEdge` -, loads and stores
     *   whose base or value is X) of the methods of both its ends: a local variable gives its method,
     *   another `GlobalVarNode` gives null (every site), an object gives `M(o)`, X itself gives its
     *   method if X is a local variable and nothing if it is global. The object end is needed: on
     *   `OBJ(o) -> F_IN(X)` and `B(X) -> OBJ(o)` the method of the path changes from the method of `o`
     *   to the one of X without a call edge, so a parenthesis of a site that reaches only the method of
     *   `o` can be open at `F_IN(X)` or closed after `B(X)` (probe P5 of critic-E6, MAJOR-1; the rule of
     *   round 1, by the method of X alone, loses those pairs).
     * Paths through other cross-method edges (an assignment between locals of two methods that is not
     * a call edge, e.g. of a reflective call) keep their stack (as `E6Reference.CsModel`), and the loop
     * sets above may miss their unmatched parentheses: their number is the counter `cross-method-assigns`.
     *
     * The answer pairs are (`OBJ(o)`, `F(v)`) in [IdrCalls.ERASED] and [IdrCalls.BALANCED], (`START(o)`,
     * `END(v)`) and (`START(o)`, `F_IN(X)`) in [IdrCalls.CS] ([IdrGraph.sourceVertex],
     * [IdrGraph.answerVertex]).
     *
     * Vertex ids, field and site indices are given in the order of first occurrence; every vertex
     * lies on an edge. [IdrGraph.sites] lists the statements of the exported call edges.
     *
     * [IdrGraph.counters]: `pagEdges` (edges read from the PAG), `droppedContextField`,
     * `droppedThisNew`, `droppedExceptionNew`, `droppedCallAssign` (PAG edges, before the CI
     * projection merges any), `callEdges` (distinct CI call edges per statement and direction),
     * `callSites`, `exceptionAssigns` (distinct CI exception assignments), `vertices`, `edges`, `fields`;
     * in [IdrCalls.BALANCED] and [IdrCalls.CS] also `jumps` (context-insensitive variables X),
     * `cross-method-new-targets` (the X that are local targets of an object with a method),
     * `methodless-new-targets` (the other local X: targets of objects without a method outside their
     * home), `cross-method-assigns` (exported
     * assignments between local variables of two methods), `gadget-start-loops`, `gadget-end-loops`,
     * `gadget-erase-loops` (self-loops of each gadget; `jumps` and the gadget counters are 0 in
     * [IdrCalls.BALANCED], which has no gadgets).
     */
    @JvmStatic
    fun export(pta: PTA, calls: IdrCalls): IdrGraph {
        val root = pta.rootNode.base()
        val callEdges = callEdges(pta)
        val callPairs = callEdges.mapTo(HashSet()) { it.from to it.to }
        val exceptions = exceptionAssigns(pta)
        val exceptionTargets = exceptions.mapTo(HashSet()) { it.second }

        val ops = ArrayList<Op>()
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
                        ops.add(Op.Alloc(o, v))
                    }
                }
                PagEdgeKind.ASSIGN -> {
                    val u = ci(e.from)
                    val v = ci(e.to)
                    if ((u to v) in callPairs) {
                        droppedCallAssign++
                    } else {
                        ops.add(Op.Assign(u, v))
                    }
                }
                PagEdgeKind.LOAD -> {
                    val fr = e.from as FieldRefNode
                    ops.add(Op.Load(ci(fr.base), fr.field, ci(e.to)))
                }
                PagEdgeKind.STORE -> {
                    val fr = e.to as FieldRefNode
                    ops.add(Op.Store(ci(e.from), ci(fr.base), fr.field))
                }
            }
        }
        callEdges.forEach { ops.add(Op.Call(it)) }
        exceptions.forEach { (t, w) -> ops.add(Op.Assign(t, w)) }

        val jumps = LinkedHashSet<Node>()
        var crossMethodNewTargets = 0
        var methodlessNewTargets = 0
        var crossMethodAssigns = 0
        if (calls == IdrCalls.CS) {
            for (op in ops) {
                op.ends().filterTo(jumps) { it is GlobalVarNode }
                if (op is Op.Alloc && isCrossMethodNew(op.o, op.v, root) && jumps.add(op.v)) {
                    crossMethodNewTargets++
                }
            }
            val homes = homes(ops)
            for (op in ops) {
                if (op is Op.Alloc && op.o.method == null && op.v is LocalVarNode && homes[op.o] != op.v.method
                    && jumps.add(op.v)
                ) {
                    methodlessNewTargets++
                }
            }
        }
        if (calls != IdrCalls.ERASED) {
            crossMethodAssigns = ops.count {
                it is Op.Assign && it.u is LocalVarNode && it.v is LocalVarNode && it.u.method != it.v.method
            }
        }

        val b = Builder(calls, jumps)
        ops.forEach { b.add(it) }
        var startLoops = 0
        var endLoops = 0
        var eraseLoops = 0
        if (calls == IdrCalls.CS) {
            val g = Gadgets(pta, b, ops, jumps)
            startLoops = g.starts()
            endLoops = g.ends()
            eraseLoops = g.erasures()
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
        if (calls != IdrCalls.ERASED) {
            counters["jumps"] = jumps.size
            counters["cross-method-new-targets"] = crossMethodNewTargets
            counters["methodless-new-targets"] = methodlessNewTargets
            counters["cross-method-assigns"] = crossMethodAssigns
            counters["gadget-start-loops"] = startLoops
            counters["gadget-end-loops"] = endLoops
            counters["gadget-erase-loops"] = eraseLoops
        }
        return IdrGraph(b.edges.toList(), b.vertices, b.fields, b.sites, calls, counters)
    }

    /**
     * A `new o -> v` of the kernel from an object of one method into a local variable of another
     * (`Finalizer.register`): `v` is then context-insensitive in [IdrCalls.CS]. ROOT and objects without
     * a method do not count (as `E6Reference.CsModel`).
     */
    private fun isCrossMethodNew(o: AllocNode, v: Node, root: AllocNode): Boolean =
        v is LocalVarNode && o != root && o.method != null && o.method != v.method

    /**
     * The home method of each object without a method that has `new` edges in [ops] into local
     * variables: the method with the most of its distinct local targets, the first such in [ops] on a
     * tie. Its local targets in other methods are context-insensitive in [IdrCalls.CS]; with one home,
     * the object is treated as an object of that method (any choice is sound, see [IdrExport.export];
     * the largest group keeps the most targets context-sensitive).
     */
    private fun homes(ops: List<Op>): Map<AllocNode, SootMethod> {
        val targets = LinkedHashMap<AllocNode, LinkedHashMap<SootMethod, MutableSet<Node>>>()
        for (op in ops) {
            if (op is Op.Alloc && op.o.method == null && op.v is LocalVarNode) {
                targets.getOrPut(op.o) { LinkedHashMap() }.getOrPut(op.v.method) { HashSet() }.add(op.v)
            }
        }
        return targets.mapValues { (_, byMethod) -> byMethod.maxBy { it.value.size }.key }
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

    /** An exported edge of the CI PAG, before it is labeled. */
    private sealed class Op {
        /** The CI nodes this edge connects. */
        abstract fun ends(): List<Node>

        data class Alloc(val o: AllocNode, val v: Node) : Op() {
            override fun ends() = listOf(o, v)
        }

        data class Assign(val u: Node, val v: Node) : Op() {
            override fun ends() = listOf(u, v)
        }

        /** `z = x.f`. */
        data class Load(val x: Node, val f: SparkField, val z: Node) : Op() {
            override fun ends() = listOf(x, z)
        }

        /** `x.f = y`. */
        data class Store(val y: Node, val x: Node, val f: SparkField) : Op() {
            override fun ends() = listOf(y, x)
        }

        data class Call(val c: CallEdge) : Op() {
            override fun ends() = listOf(c.from, c.to)
        }
    }

    /**
     * Collects vertices, fields, sites and labeled edges in the order of first occurrence. An edge into
     * a node of [jumps] (the context-insensitive variables of [IdrCalls.CS]) enters its `F_IN`/`B_IN`.
     */
    private class Builder(val calls: IdrCalls, val jumps: Set<Node>) {
        val vertices = ArrayList<IdrVertex>()
        private val vertexIds = HashMap<IdrVertex, Int>()
        val fields = ArrayList<SparkField>()
        private val fieldIds = HashMap<SparkField, Int>()
        val sites = ArrayList<soot.Unit>()
        val siteIds = HashMap<soot.Unit, Int>()
        val edges = LinkedHashSet<LabeledEdge>()

        fun id(node: Node, layer: Layer): Int {
            val v = IdrVertex(node, layer)
            return vertexIds.getOrPut(v) { vertices.add(v); vertices.size - 1 }
        }

        /** The vertex an edge into [node] in layer [layer] (F or B) enters. */
        private fun into(node: Node, layer: Layer): Int = when {
            node !in jumps -> id(node, layer)
            layer == Layer.F -> id(node, Layer.F_IN)
            else -> id(node, Layer.B_IN)
        }

        private fun field(f: SparkField): Int = fieldIds.getOrPut(f) { fields.add(f); fields.size - 1 }

        private fun site(s: soot.Unit): Int = siteIds.getOrPut(s) { sites.add(s); sites.size - 1 }

        /** Adds an edge; false if it was there. */
        fun edge(from: Int, label: String, to: Int): Boolean = edges.add(LabeledEdge(from, label, to))

        fun add(op: Op) {
            when (op) {
                is Op.Alloc -> alloc(op.o, op.v)
                is Op.Assign -> assign(op.u, op.v)
                is Op.Load -> load(op.x, op.f, op.z)
                is Op.Store -> store(op.y, op.x, op.f)
                is Op.Call -> call(op.c)
            }
        }

        private fun alloc(o: Node, v: Node) {
            edge(id(o, Layer.OBJ), NORMAL, into(v, Layer.F))
            edge(id(v, Layer.B), NORMAL, id(o, Layer.OBJ))
        }

        private fun assign(u: Node, v: Node) {
            edge(id(u, Layer.F), NORMAL, into(v, Layer.F))
            edge(id(v, Layer.B), NORMAL, into(u, Layer.B))
        }

        /** `x.f = y`: opens the store bracket into B, and closes the reversed bracket store-bar. */
        private fun store(y: Node, x: Node, f: SparkField) {
            val i = field(f)
            edge(id(y, Layer.F), "ob--$i", into(x, Layer.B))
            edge(id(x, Layer.F), "cb--${i}r", into(y, Layer.B))
        }

        /** `z = x.f`: closes the store bracket in F, and opens the reversed bracket load-bar in B. */
        private fun load(x: Node, f: SparkField, z: Node) {
            val i = field(f)
            edge(id(x, Layer.F), "cb--$i", into(z, Layer.F))
            edge(id(z, Layer.B), "ob--${i}r", into(x, Layer.B))
        }

        /** An entry opens the parenthesis of its site in F and closes it in B; an exit the other way round. */
        private fun call(c: CallEdge) {
            val s = site(c.site)
            if (calls == IdrCalls.ERASED) {
                assign(c.from, c.to)
                return
            }
            val forward = if (c.entry) "op--$s" else "cp--$s"
            val backward = if (c.entry) "cp--$s" else "op--$s"
            edge(id(c.from, Layer.F), forward, into(c.to, Layer.F))
            edge(id(c.to, Layer.B), backward, into(c.from, Layer.B))
        }
    }

    /**
     * The START, END and erasure gadgets of [IdrCalls.CS] and their loops (see [IdrExport.export]),
     * added to [b] after all edges of [ops], so that the site indices are final.
     */
    private class Gadgets(pta: PTA, val b: Builder, val ops: List<Op>, val jumps: Set<Node>) {
        private val reach = SiteReach(pta, b.siteIds)
        private val allSites = BitSet().apply { set(0, b.sites.size) }
        private val allocTargets = HashMap<Node, MutableList<Node>>()

        init {
            for (op in ops) {
                if (op is Op.Alloc) {
                    allocTargets.getOrPut(op.o) { ArrayList() }.add(op.v)
                }
            }
        }

        /** A set of methods, or every method when [all]. */
        private class Methods {
            val methods = LinkedHashSet<SootMethod>()
            var all = false

            fun add(m: SootMethod?) {
                if (m == null) all = true else methods.add(m)
            }
        }

        private fun sites(ms: Methods): BitSet {
            if (ms.all) {
                return allSites
            }
            val out = BitSet()
            ms.methods.forEach { out.or(reach.of(it)) }
            return out
        }

        /**
         * M(o): the method of [o], or the methods of its local targets that are not context-insensitive
         * (its home method, or none).
         */
        private fun objectMethods(o: AllocNode, into: Methods) {
            if (o.method != null) {
                into.add(o.method)
                return
            }
            for (v in allocTargets[o].orEmpty()) {
                if (v is LocalVarNode && v !in jumps) {
                    into.add(v.method)
                }
            }
        }

        /** Adds the methods that end [n] of an edge incident to the context-insensitive [x] gives to M(x). */
        private fun endMethods(n: Node, x: Node, into: Methods) {
            when (n) {
                x -> if (n is LocalVarNode) into.add(n.method)
                is AllocNode -> objectMethods(n, into)
                is LocalVarNode -> into.add(n.method)
                else -> into.all = true // another GlobalVarNode
            }
        }

        private fun loops(v: Int, open: Boolean, sites: BitSet): Int {
            val p = if (open) "op--" else "cp--"
            var n = 0
            var c = sites.nextSetBit(0)
            while (c >= 0) {
                if (b.edge(v, "$p$c", v)) {
                    n++
                }
                c = sites.nextSetBit(c + 1)
            }
            return n
        }

        /** `START(o) -normal-> OBJ(o)`, loops `op--c` by the sites of M(o). Returns the number of loops. */
        fun starts(): Int {
            var n = 0
            val objects = b.vertices.filter { it.layer == Layer.OBJ }.map { it.node as AllocNode }
            for (o in objects) {
                val start = b.id(o, Layer.START)
                b.edge(start, NORMAL, b.id(o, Layer.OBJ))
                n += loops(start, true, sites(Methods().also { objectMethods(o, it) }))
            }
            return n
        }

        /** `F(v) -normal-> END(v)` for each variable but X, loops `cp--c` by the sites of its method. */
        fun ends(): Int {
            var n = 0
            val vars = b.vertices.filter { it.layer == Layer.F && it.node !in jumps }.map { it.node as LocalVarNode }
            for (v in vars) {
                val end = b.id(v, Layer.END)
                b.edge(b.id(v, Layer.F), NORMAL, end)
                n += loops(end, false, sites(Methods().also { it.add(v.method) }))
            }
            return n
        }

        /** `F_IN(X) -> F(X)`, `B_IN(X) -> B(X)` and their loops by the sites of M(X), for each X. */
        fun erasures(): Int {
            val ms = LinkedHashMap<Node, Methods>()
            jumps.forEach { ms[it] = Methods() }
            for (op in ops) {
                val ends = op.ends()
                for (x in ends) {
                    val m = ms[x] ?: continue
                    ends.forEach { endMethods(it, x, m) }
                }
            }
            var n = 0
            for ((x, m) in ms) {
                val sites = sites(m)
                val fin = b.id(x, Layer.F_IN)
                val f = b.id(x, Layer.F)
                val bin = b.id(x, Layer.B_IN)
                val bx = b.id(x, Layer.B)
                b.edge(fin, NORMAL, f)
                b.edge(bin, NORMAL, bx)
                n += loops(fin, false, sites) + loops(bin, false, sites) + loops(f, true, sites) + loops(bx, true, sites)
            }
            return n
        }
    }

    /**
     * For each method `m`, the sites (indices of [IdrGraph.sites]) one of whose callees reaches `m` in
     * `PTA.getCallGraph()` (transitively; a callee reaches itself). Fixpoint over the call graph:
     * the set of `m` holds the sites that call `m` and the set of every caller of `m`.
     */
    private class SiteReach(pta: PTA, siteIds: Map<soot.Unit, Int>) {
        private val reach = HashMap<SootMethod, BitSet>()

        init {
            val callees = HashMap<SootMethod, MutableSet<SootMethod>>()
            for (e in pta.callGraph) {
                val src = e.src() ?: continue
                val tgt = e.tgt() ?: continue
                callees.getOrPut(src) { LinkedHashSet() }.add(tgt)
                val c = e.srcUnit()?.let { siteIds[it] }
                if (c != null) {
                    reach.getOrPut(tgt) { BitSet() }.set(c)
                }
            }
            val work = ArrayDeque(reach.keys)
            val queued = HashSet(work)
            while (work.isNotEmpty()) {
                val t = work.removeFirst()
                queued.remove(t)
                val r = reach.getValue(t)
                for (m in callees[t].orEmpty()) {
                    val rm = reach.getOrPut(m) { BitSet() }
                    val before = rm.cardinality()
                    rm.or(r)
                    if (rm.cardinality() != before && queued.add(m)) {
                        work.addLast(m)
                    }
                }
            }
        }

        fun of(m: SootMethod): BitSet = reach[m] ?: EMPTY

        private companion object {
            val EMPTY = BitSet()
        }
    }

    private const val NORMAL = "normal"
}
