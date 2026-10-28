package qilin.test.ucfs;

import driver.PTAOption;
import driver.PTAPattern;
import org.junit.Test;
import qilin.pta.PTAConfig;
import qilin.pta.ucfs.CflIdrRun;

import java.util.concurrent.atomic.AtomicLong;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

/**
 * E6-S5, the real stack of the thread of cfl-idr (ticket E6-S5, "Дополнение лида (2026-10-27)", O5e; E6.md
 * D14). Not an acceptance test of the plan: the implementer's own check that the thread that
 * {@link CflIdrRun#run} starts for the export and cfl-idr ({@link CflIdrRun#runOnThread}) really gets the
 * stack of {@code -cflidrstack}, by its default value, and not just prints it in {@code #CFLIDR-stack}.
 *
 * <p>The stack size comes from the command line as driver.Main reads it ({@link PTAOption} on
 * {@code -cflidr=parity}, without {@code -cflidrstack}, into {@code PTAConfig.v().cflIdrStack}); the
 * recursion of {@value #DEPTH} frames with four live {@code long} values per frame needs far more than
 * 1 MB (the default stack of a Java thread on Linux x86-64): the test {@link #oneMegabyteIsTooSmall} shows
 * that it overflows a stack of 1 MB through the same {@link CflIdrRun#runOnThread}. So a thread without a
 * stack size, or with 1 MB, fails {@link #defaultStackHoldsADeepRecursion}.
 */
public class E6CflIdrStackTest {
    static final int DEPTH = 500_000;

    @Test
    public void defaultStackHoldsADeepRecursion() {
        long stack = stackOfCommandLine("-cflidr=parity");
        assertEquals("default of -cflidrstack", 1L << 30, stack);
        AtomicLong result = new AtomicLong(-1);
        Throwable t = CflIdrRun.runOnThread(stack, () -> result.set(depth(DEPTH, 1, 2, 3)));
        assertNull("recursion of " + DEPTH + " frames on the default stack: " + (t == null ? "" : CflIdrRun.report(t, "export")), t);
        assertEquals(DEPTH * 6L, result.get());
    }

    @Test
    public void stackOptionSetsTheSize() {
        assertEquals(256L << 20, stackOfCommandLine("-cflidr=parity", "-cflidrstack=256m"));
        assertEquals(64L << 10, stackOfCommandLine("-cflidr=parity", "-cflidrstack=64K"));
        assertEquals(2L << 30, stackOfCommandLine("-cflidr=parity", "-cflidrstack=2g"));
        assertEquals(12345L, stackOfCommandLine("-cflidr=parity", "-cflidrstack=12345"));
    }

    @Test
    public void oneMegabyteIsTooSmall() {
        Throwable t = CflIdrRun.runOnThread(1L << 20, () -> depth(DEPTH, 1, 2, 3));
        assertTrue("recursion of " + DEPTH + " frames on 1 MB: " + t, t instanceof StackOverflowError);
    }

    /** The failure report of a thread that overflows its stack, in the format {@code acceptance/E6/S5_cli.sh} reads. */
    @Test
    public void reportOfAStackOverflow() {
        Throwable t = CflIdrRun.runOnThread(64L << 10, () -> depth(DEPTH, 1, 2, 3));
        assertTrue(String.valueOf(t), t instanceof StackOverflowError);
        String[] lines = CflIdrRun.report(t, "under").split("\n", -1);
        int depth = t.getStackTrace().length;
        int frames = Math.min(CflIdrRun.REPORT_FRAMES, depth);
        assertTrue(depth > 0);
        assertEquals("#CFLIDR-error: java.lang.StackOverflowError at under", lines[0]);
        assertEquals("#CFLIDR-error-depth: " + depth, lines[1]);
        assertEquals("java.lang.StackOverflowError", lines[2]);
        assertEquals(3 + frames + 1, lines.length);
        for (int i = 3; i < 3 + frames; i++) {
            assertTrue(lines[i], lines[i].startsWith("\tat "));
        }
        assertEquals("", lines[lines.length - 1]);
    }

    @Test
    public void normalEndAndException() {
        assertNull(CflIdrRun.runOnThread(1L << 20, () -> { }));
        Throwable t = CflIdrRun.runOnThread(1L << 20, () -> {
            throw new IllegalStateException("x\ny");
        });
        assertTrue(t instanceof IllegalStateException);
        assertTrue(CflIdrRun.report(t, "dump").startsWith(
                "#CFLIDR-error: java.lang.IllegalStateException at dump\n#CFLIDR-error-depth: "));
        assertTrue(CflIdrRun.report(t, "dump").contains("\njava.lang.IllegalStateException: x y\n\tat "));
    }

    /** An OutOfMemoryError of the thread is returned like any throwable (one array larger than the heap of any test JVM). */
    @Test
    public void outOfMemoryIsReturned() {
        Throwable t = CflIdrRun.runOnThread(1L << 20, () -> {
            long[] huge = new long[Integer.MAX_VALUE - 8];
            huge[0] = 1;
        });
        assertTrue(String.valueOf(t), t instanceof OutOfMemoryError);
        assertTrue(CflIdrRun.report(t, "over").startsWith("#CFLIDR-error: java.lang.OutOfMemoryError at over\n"));
    }

    private static long depth(int n, long a, long b, long c) {
        if (n == 0) {
            return 0;
        }
        return depth(n - 1, a, b, c) + a + b + c;
    }

    /**
     * {@code PTAConfig.v().cflIdrStack} after parsing {@code args} as driver.Main does. The fields of the
     * singleton that the parse sets are restored afterwards: the other tests of this JVM share it.
     */
    private static long stackOfCommandLine(String... args) {
        PTAConfig c = PTAConfig.v();
        PTAPattern pattern = c.getPtaConfig().ptaPattern;
        String name = c.getPtaConfig().ptaName;
        String grammar = c.cflIdrGrammar;
        String mode = c.cflIdrMode;
        long stack = c.cflIdrStack;
        try {
            new PTAOption().parseCommandLine(args);
            return PTAConfig.v().cflIdrStack;
        } finally {
            c.getPtaConfig().ptaPattern = pattern;
            c.getPtaConfig().ptaName = name;
            c.cflIdrGrammar = grammar;
            c.cflIdrMode = mode;
            c.cflIdrStack = stack;
        }
    }
}
