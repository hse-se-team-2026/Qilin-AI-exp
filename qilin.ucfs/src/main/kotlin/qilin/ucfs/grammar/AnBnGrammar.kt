package qilin.ucfs.grammar

import org.ucfs.grammar.combinator.Grammar
import org.ucfs.grammar.combinator.regexp.Nt
import org.ucfs.grammar.combinator.regexp.Option
import org.ucfs.grammar.combinator.regexp.times
import org.ucfs.rsm.symbol.Term

/**
 * The grammar `S -> a S? b`, that is `a^n b^n` for `n >= 1`, with terminals `Term(a)` and `Term(b)`.
 *
 * The terminals match edges labeled [a] and [b] in [qilin.ucfs.UcfsSolver.reachablePairs]
 * (`Term` is compared by value). The start nonterminal does not accept the empty word, so no
 * pair `(v, v)` is reported. One instance can be passed to many queries: its RSM is built once.
 *
 * @param a the label of the opening edge
 * @param b the label of the closing edge
 */
class AnBnGrammar(a: String, b: String) : Grammar() {
    /** The start nonterminal. */
    val S by Nt().asStart()

    init {
        S /= Term(a) * Option(S) * Term(b)
    }
}
