#!/usr/bin/env bash
# critic-E6 probes of the E6 plan (docs/ai/tickets/E6.md, section "Critic"). Each probe has its own
# header. Inputs are hand-made graphs/PAGs (no E6 implementation exists yet); solvers: the cfl-idr CLI
# of the root build (libs/solver-new.jar = UCFS PR #50) and, in P2, cfl-idr src/main compiled against
# UCFS-AI-dev bd1c111 (p2_sof_xss/bd1c111-build). All JVMs here use <= 4 GB heap (RAM rule: no lock).
#   P1 p1_bracket_kind         D4 field encoding vs mutant M1 on the PAG of ArrayElemTypeFiltering;
#                              acceptance/E6/IdrDyckCheck.java on both dumps
#   P2 p2_sof_xss              StackOverflowError of the RSM build vs id count and -Xss, both UCFS versions
#   P3 p3_ram_lock             heaps/locks in acceptance/E6; nested flock on one lock file
#   P4 p4_s6_status            S6_probe.sh runs/values checks on synthetic results with swapped statuses
#   P5 p5_cross_method_erasure CS loops at a cross-method `new` target (E6-S4 rule vs fix)
# Usage: CFLIDR_JAR=<cfl-idr-with-gll-all.jar> bash critic/E6/run_all.sh <out-dir>   (P2 ~ 25 min)
set -u
H="$(cd "$(dirname "$0")" && pwd)"; O="$1"; mkdir -p "$O"
bash "$H/p1_bracket_kind/run.sh" "$O/p1"
bash "$H/p3_ram_lock/run.sh" "$O/p3"
bash "$H/p4_s6_status/run.sh" "$O/p4"
bash "$H/p5_cross_method_erasure/run.sh" "$O/p5"
bash "$H/p2_sof_xss/run.sh" "$O/p2"
bash "$H/p2_sof_xss/run-bd1c111.sh" "$O/p2b" 2650:194 19271:301
