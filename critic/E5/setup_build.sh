#!/usr/bin/env bash
# critic-E5: worktree preparation (the order of the E5 tickets) and a fat jar of HEAD for the real probes.
set -eu
cd "$(dirname "$0")/../.."
export JAVA_HOME=$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2
git submodule update --init qilin.microben
git submodule update --init --depth 1 artifact/benchmarks
bash scripts/ucfs/bootstrap.sh
bash ./gradlew build -x test
bash ./gradlew fatJar -x test
git checkout -- artifact/Qilin-0.9.9-SNAPSHOT.jar
cp build/libs/Qilin-0.9.9-SNAPSHOT.jar critic/E5/out/qilin-fat.jar
sha256sum critic/E5/out/qilin-fat.jar
