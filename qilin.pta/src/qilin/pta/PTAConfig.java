/* Qilin - a Java Pointer Analysis Framework
 * Copyright (C) 2021 Dongjie He
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, either version 3.0 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Lesser Public License for more details.
 *
 * You should have received a copy of the GNU General Lesser Public
 * License along with this program.  If not, see
 * <https://www.gnu.org/licenses/lgpl-3.0.en.html>.
 */

package qilin.pta;

import driver.PTAPattern;
import qilin.CoreConfig;
import qilin.pta.tools.DebloatedPTA;
import qilin.ucfs.ReceiverBinding;

public class PTAConfig extends CoreConfig {
    private static PTAConfig config = null;

    public static PTAConfig v() {
        if (config == null) {
            config = new PTAConfig();
            coreConfig = config;
        }
        return config;
    }

    public static void reset() {
        CoreConfig.reset();
        config = null;
    }

    public static class PointerAnalysisConfiguration extends CorePTAConfiguration {
        public PTAPattern ptaPattern;

        /**
         * If this option is turned on, then main analysis will not run.
         */
        public boolean preAnalysisOnly = false;

        /**
         * If this option is turned on, we will apply context debloating techniques.
         */
        public boolean ctxDebloating = false;
        public DebloatedPTA.DebloatApproach debloatApproach = DebloatedPTA.DebloatApproach.CONCH;

    }

    /*
     * Notice that the DEFAULT option is equivalent to Full Turner.
     * PHASE_TWO: all objects are assumed to be CS-likely.
     * PHASE_ONE: only non-CS-likely objects are analyzed context-insensitively. All other variables and objects
     * are analyzed context-sensitively.
     * */
    public enum TurnerConfig {
        DEFAULT, PHASE_TWO, PHASE_ONE
    }

    public TurnerConfig turnerConfig = TurnerConfig.DEFAULT;

    private PTAConfig() {
        this.ptaConfig = new PointerAnalysisConfiguration();
    }

    public PointerAnalysisConfiguration getPtaConfig() {
        return (PointerAnalysisConfiguration) this.ptaConfig;
    }

    /*
     * Configures the callgraph options
     * */
    public enum CallgraphAlgorithm {
        /*CHA, VTA, RTA, GEOM, and SPARK are all provided by Soot */
        CHA, VTA, RTA, GEOM, SPARK, QILIN
    }

    public CallgraphAlgorithm callgraphAlg = CallgraphAlgorithm.QILIN;

    /**
     * If this option is turned on (-ucfsseam), driver.Main prints the edge counts of the global PAG
     * after the analysis (qilin.pta.ucfs.UcfsSeam).
     */
    public boolean ucfsSeam = false;

    /**
     * If this option is turned on (-ucfspt), driver.Main runs UCFS points-to on the exported PAG
     * after the analysis and dumps the graph and the answer to outDir/ucfs
     * (qilin.pta.ucfs.UcfsPointsToDump); with -pta=ucfs it dumps the graph and the answer of
     * that analysis, without running UCFS again.
     */
    public boolean ucfsPointsTo = false;

    /**
     * How the analysis {@code -pta=ucfs} ({@code qilin.pta.tools.UcfsPTA}) binds receivers to
     * {@code this} in its export (-ucfsbinding, E4-S2); read only by that analysis.
     */
    public ReceiverBinding ucfsBinding = ReceiverBinding.ANALYSIS;

    /**
     * If this option is turned on (-ucfscompare, only with -pta=ucfs), driver.Main compares the
     * views of that analysis after the run and writes outDir/ucfs-compare (qilin.pta.ucfs.UcfsCompare, E4-S3).
     */
    public boolean ucfsCompare = false;

    /**
     * If set (-cflidr=&lt;grammar&gt;, E6-S5), driver.Main exports the PAG of the analysis for cfl-idr-with-gll,
     * runs cfl-idr with this grammar (a key of {@code qilin.ucfs.idr.IdrSolve.GRAMMARS}) and dumps the
     * graph and the answer to outDir/cflidr (qilin.pta.ucfs.CflIdrRun); {@code null}: not run.
     */
    public String cflIdrGrammar = null;

    /**
     * How the export labels the call edges (-cflidrmode, only with -cflidr): the name of a constant of
     * {@code qilin.ucfs.idr.IdrCalls} ({@code ERASED}, {@code BALANCED}, {@code CS}). A string, so that a run
     * without -cflidr loads no class of qilin.ucfs.idr.
     */
    public String cflIdrMode = "CS";

    /**
     * Stack size in bytes of the thread that runs the export, cfl-idr and the dump (-cflidrstack, only
     * with -cflidr); 1 GB by default.
     */
    public long cflIdrStack = 1L << 30;
}
