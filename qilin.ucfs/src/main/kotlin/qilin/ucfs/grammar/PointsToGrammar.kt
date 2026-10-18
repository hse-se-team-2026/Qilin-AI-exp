package qilin.ucfs.grammar

import org.ucfs.grammar.combinator.Grammar
import org.ucfs.grammar.combinator.regexp.Nt
import org.ucfs.grammar.combinator.regexp.Regexp
import org.ucfs.grammar.combinator.regexp.many
import org.ucfs.grammar.combinator.regexp.or
import org.ucfs.grammar.combinator.regexp.times
import org.ucfs.rsm.symbol.Term
import qilin.ucfs.PtLabels

/**
 * The field-sensitive points-to language L_FT of Sridharan et al. 2005 (`Sridharan2005Demand`,
 * Fig. 3, p. 6) over the fields `0 until fieldCount`, with the start nonterminal [flowsTo]:
 *
 * ```
 * flowsTo    -> new step*                 flowsTo of Fig. 3: new (assign | store[f] alias load[f])*
 * step       -> assign | store[f] alias load[f]
 * flowsToBar -> stepBar* new_bar          flowsTo~ of Fig. 3: (assign~ | load[f]~ alias store[f]~)* new~
 * stepBar    -> assign_bar | load[f]_bar alias store[f]_bar
 * alias      -> flowsToBar flowsTo
 * ```
 *
 * [step] and [stepBar] only name the starred groups of Fig. 3, so the language of [flowsTo] is
 * the one of the figure. A pair `(o, v)` in the answer means that the object `o` may flow to the
 * variable `v`, on the graph of [qilin.ucfs.PagExport]: edges go from the object to the variable
 * (`o -new-> v`), and an edge `u -l-> v` comes with the reversed edge `v -l_bar-> u`.
 *
 * Fields: UCFS has no terminals with parameters, so field `i` has its own terminals
 * `Term(PtLabels.store(i))` and `Term(PtLabels.load(i))` (and their `PtLabels.bar` versions), and
 * the rules of [step] and [stepBar] repeat the alternative with `store_i alias load_i` once per
 * field. The same `i` on both sides of `alias` is what keeps different fields apart. Terminals are
 * built through [PtLabels], not from string literals.
 *
 * The `fieldCount + 1` alternatives of [step] (and of [stepBar]) are joined by a balanced tree of
 * `or` (depth about `log2(fieldCount)`), not by a left fold `reduce { a, b -> a or b }`: the RSM
 * builder walks the regexp recursively (`getAlphabet`, `derive`, `equals`/`hashCode`), and a
 * left-deep chain of thousands of `Alternative`s throws StackOverflowError (skill ucfs,
 * `references/grammar-dsl.md`, "Known RSM-building failure"). Moving the alternatives into their own
 * nonterminals keeps them out of the RSM states of [flowsTo] and [flowsToBar], which roughly halved
 * the RSM build time for 2000 fields in one measurement (decision recorded in E3-S2.md). The RSM is
 * still built by the DSL derivative construction, whose cost grows with the number of fields times
 * the alphabet size; it is built once per instance (lazy `rsm`), so reuse one instance across
 * queries.
 *
 * @param fieldCount the number of fields, `>= 0`; field indices are `0 until fieldCount`
 */
class PointsToGrammar(fieldCount: Int) : Grammar() {
    /** The start nonterminal: `flowsTo` of Fig. 3. */
    val flowsTo by Nt().asStart()

    /** `flowsTo` read backwards (the overlined `flowsTo` of Fig. 3), over the `_bar` labels. */
    val flowsToBar by Nt()

    /** `alias -> flowsToBar flowsTo`: two variables that may point to the same object. */
    val alias by Nt()

    /** One step of the star in `flowsTo`: `assign | store_i alias load_i` for each field `i`. */
    val step by Nt()

    /** One step of the star in `flowsToBar`: `assign_bar | load_i_bar alias store_i_bar` for each field `i`. */
    val stepBar by Nt()

    init {
        require(fieldCount >= 0) { "fieldCount must be >= 0, got $fieldCount" }
        val fields = 0 until fieldCount
        val forward = listOf<Regexp>(term(PtLabels.ASSIGN)) +
            fields.map { term(PtLabels.store(it)) * alias * term(PtLabels.load(it)) }
        val backward = listOf<Regexp>(barTerm(PtLabels.ASSIGN)) +
            fields.map { barTerm(PtLabels.load(it)) * alias * barTerm(PtLabels.store(it)) }

        step /= balancedOr(forward)
        stepBar /= balancedOr(backward)
        flowsTo /= term(PtLabels.NEW) * many(step)
        flowsToBar /= many(stepBar) * barTerm(PtLabels.NEW)
        alias /= flowsToBar * flowsTo
    }

    private companion object {
        fun term(label: String): Term<String> = Term(label)

        fun barTerm(label: String): Term<String> = Term(PtLabels.bar(label))

        /** `alts[0] or ... or alts[n-1]` as a tree of depth about `log2(n)`; [alts] is not empty. */
        fun balancedOr(alts: List<Regexp>): Regexp =
            if (alts.size == 1) alts[0]
            else {
                val mid = alts.size / 2
                balancedOr(alts.subList(0, mid)) or balancedOr(alts.subList(mid, alts.size))
            }
    }
}
