package qilin.ucfs

/**
 * The boundaries of consecutive phases of one run on the `System.nanoTime` clock (E5-S1).
 *
 * [start] is read when the object is made; [end] of a phase is one `System.nanoTime` read, which
 * is both the end of that phase and the start of the next one. So the phases are disjoint, follow
 * each other without gaps and their durations sum to [end] − [start] exactly. A phase name is
 * ended at most once, so its duration is set once and never accumulated.
 *
 * Not thread-safe: one run on one thread ends its phases on its own object.
 */
class PhaseMarks {

    /** The `System.nanoTime` read at the creation of this object: the start of the first phase. */
    val start: Long = System.nanoTime()

    private val names = ArrayList<String>()
    private val ends = ArrayList<Long>()

    /** The end of the last phase ended so far; [start] when no phase has been ended. */
    val end: Long
        get() = if (ends.isEmpty()) start else ends[ends.size - 1]

    /**
     * Ends the phase [phase] now: its start is the end of the previous phase ([start] for the first).
     *
     * @return the `System.nanoTime` read that ends the phase
     * @throws IllegalArgumentException if [phase] has already been ended on this object
     */
    fun end(phase: String): Long {
        require(phase !in names) { "phase $phase ended twice" }
        val t = System.nanoTime()
        names.add(phase)
        ends.add(t)
        return t
    }

    /** Phase name -> nanoseconds from the end of the previous phase to its own end, in the order they were ended. */
    fun durations(): LinkedHashMap<String, Long> {
        val out = LinkedHashMap<String, Long>()
        var prev = start
        for (i in names.indices) {
            out[names[i]] = ends[i] - prev
            prev = ends[i]
        }
        return out
    }
}
