package qilin.ucfs

/**
 * Edge labels of the points-to input graph built by [PagExport] (E3.md D4).
 *
 * The strings are part of the contract (E3.md D4): [NEW] = `"new"`, [ASSIGN] = `"assign"`,
 * `store(i)` = `"store_$i"`, `load(i)` = `"load_$i"`, [BAR_SUFFIX] = `"_bar"` and
 * `bar(l)` = `l + BAR_SUFFIX`. A grammar should still build its terminals through these
 * functions rather than repeat the strings.
 *
 * The forward labels are pairwise distinct (different prefixes, and `i` is a decimal number), and
 * none of them ends with [BAR_SUFFIX], so `bar(l) != l` and a reversed label never equals a
 * forward one.
 */
object PtLabels {
    /** `o -new-> v`: the variable `v` may hold the object `o` (map `PAG.getAlloc()`). */
    const val NEW: String = "new"

    /** `u -assign-> v`: a copy from `u` to `v` (map `PAG.getSimple()`). */
    const val ASSIGN: String = "assign"

    /** Suffix that [bar] appends to a label to name the reversed edge. */
    const val BAR_SUFFIX: String = "_bar"

    /** Label of `y -store_i-> x` for `x.f = y`, where `i` is the dense index of the field `f`. */
    @JvmStatic
    fun store(field: Int): String = "store_$field"

    /** Label of `x -load_i-> z` for `z = x.f`, where `i` is the dense index of the field `f`. */
    @JvmStatic
    fun load(field: Int): String = "load_$field"

    /** Label of the reversed edge `v -bar(l)-> u` added for an edge `u -l-> v`. */
    @JvmStatic
    fun bar(label: String): String = label + BAR_SUFFIX
}
