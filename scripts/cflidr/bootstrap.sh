#!/usr/bin/env bash
# Builds cfl-idr-with-gll (cfl-idr-with-gll-AI-exp) at the commit pinned in scripts/cflidr/cflidr.properties
# against the UCFS of Qilin and publishes org.cfl_idr_with_gll:cfl-idr-with-gll:<cflidrVersion> into the
# project-local Maven repository .cflidr/m2, which qilin.ucfs/build.gradle reads. The UCFS comes first:
# scripts/ucfs/bootstrap.sh publishes org.ucfs:solver (ucfsCommit of gradle.properties) into .ucfs/m2, and
# cfl-idr is compiled against exactly that solver, so the JVM of Qilin has one UCFS.
# Nothing is written outside .ucfs/ and .cflidr/ (not to ~/.m2).
#
#   scripts/cflidr/cflidr.properties: cflidrVersion, cflidrCommit, cflidrGitUrl
#   CFLIDR_SRC=<git URL | path>   take the cfl-idr sources from here instead of cflidrGitUrl
#                                 (must contain cflidrCommit)
#   .cflidr/src                   cfl-idr-with-gll checkout (detached at cflidrCommit)
#   .cflidr/m2                    Maven repository with org.cfl_idr_with_gll:cfl-idr-with-gll
#
# The build is the standalone build ucfs-main/ of the pinned commit (main code of cfl-idr-with-gll, Kotlin
# 2.4.0, compiled against -PucfsRepo=.ucfs/m2), run by cfl-idr's own Gradle wrapper (Gradle 8.14) in a
# separate process. It needs a JDK 17..24 in JAVA_HOME (or on PATH) to run Gradle, e.g. the JDK 21 of
# Qilin; the toolchain JDK 21 is found or downloaded by Gradle. The tests of cfl-idr are not run here
# (acceptance/E6/S1_ucfs_main.sh of cfl-idr-with-gll-AI-exp runs them).
# If .cflidr/m2 already has the jar built from cflidrCommit against ucfsCommit, nothing is rebuilt.
# Usage: bash scripts/cflidr/bootstrap.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROPS="$ROOT/scripts/cflidr/cflidr.properties"
GRADLE_PROPS="$ROOT/gradle.properties"

die() { echo "bootstrap.sh: $*" >&2; exit 1; }
# prop <file> <key> -> value of key in a .properties file
prop() { sed -n "s/^$2=//p" "$1" | tail -n 1 | tr -d '\r'; }
# manifest_attr <jar> <name> -> value of a jar manifest attribute (empty if absent)
manifest_attr() { unzip -p "$1" META-INF/MANIFEST.MF | tr -d '\r' | sed -n "s/^$2: //p"; }

command -v git >/dev/null || die "git is required"
command -v unzip >/dev/null || die "unzip is required"
[ -f "$PROPS" ] || die "no $PROPS"

VERSION="$(prop "$PROPS" cflidrVersion)"
COMMIT="$(prop "$PROPS" cflidrCommit)"
SRC_URL="${CFLIDR_SRC:-$(prop "$PROPS" cflidrGitUrl)}"
UCFS_VERSION="$(prop "$GRADLE_PROPS" ucfsVersion)"
UCFS_COMMIT="$(prop "$GRADLE_PROPS" ucfsCommit)"
[ -n "$VERSION" ] || die "no cflidrVersion in $PROPS"
echo "$COMMIT" | grep -qxE '[0-9a-f]{40}' || die "cflidrCommit in $PROPS is not a 40-hex commit: '$COMMIT'"
[ -n "$SRC_URL" ] || die "no cflidrGitUrl in $PROPS (and CFLIDR_SRC is not set)"

# UCFS first: cfl-idr is compiled against the solver in .ucfs/m2.
bash "$ROOT/scripts/ucfs/bootstrap.sh"
UCFS_M2="$ROOT/.ucfs/m2"
[ -f "$UCFS_M2/org/ucfs/solver/$UCFS_VERSION/solver-$UCFS_VERSION.jar" ] \
    || die "no org.ucfs:solver:$UCFS_VERSION in $UCFS_M2 after scripts/ucfs/bootstrap.sh"

DIR="$ROOT/.cflidr"
SRC="$DIR/src"
M2="$DIR/m2"
JAR="$M2/org/cfl_idr_with_gll/cfl-idr-with-gll/$VERSION/cfl-idr-with-gll-$VERSION.jar"
POM="$M2/org/cfl_idr_with_gll/cfl-idr-with-gll/$VERSION/cfl-idr-with-gll-$VERSION.pom"

# Already published from the pinned commit, clean, against the pinned UCFS: nothing to do.
if [ -f "$JAR" ] && [ -f "$POM" ] \
    && [ "$(manifest_attr "$JAR" CflIdr-Commit)" = "$COMMIT" ] \
    && [ "$(manifest_attr "$JAR" CflIdr-Dirty)" = "false" ] \
    && [ "$(manifest_attr "$JAR" UCFS-Commit)" = "$UCFS_COMMIT" ]; then
    echo "cfl-idr org.cfl_idr_with_gll:cfl-idr-with-gll:$VERSION @ $COMMIT (UCFS @ $UCFS_COMMIT) is already in $M2 (nothing to do)"
    exit 0
fi

# Sources: clone once, then reuse .cflidr/src and fetch the pinned commit if it is missing.
mkdir -p "$DIR"
if [ ! -d "$SRC/.git" ]; then
    rm -rf "$SRC"   # leftover of an interrupted clone (only inside .cflidr/)
    echo "cloning $SRC_URL into $SRC"
    git clone -q --no-checkout "$SRC_URL" "$SRC"
else
    git -C "$SRC" remote set-url origin "$SRC_URL"
fi
if ! git -C "$SRC" cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
    echo "fetching $COMMIT from $SRC_URL"
    git -C "$SRC" fetch -q origin || true
    git -C "$SRC" cat-file -e "$COMMIT^{commit}" 2>/dev/null \
        || git -C "$SRC" fetch -q origin "$COMMIT" \
        || die "commit $COMMIT not found in $SRC_URL"
fi
# Do not silently throw away edits someone made in .cflidr/src. A --no-checkout clone has no
# index yet (every file would look deleted), so only an existing checkout is checked.
if [ -f "$SRC/.git/index" ] && [ -n "$(git -C "$SRC" status --porcelain --untracked-files=no)" ]; then
    die "$SRC has local changes to tracked files; save them elsewhere or delete $SRC"
fi
git -C "$SRC" -c advice.detachedHead=false checkout -q --detach "$COMMIT"
[ -f "$SRC/ucfs-main/build.gradle.kts" ] || die "cflidrCommit $COMMIT has no ucfs-main/build.gradle.kts (not after E6-S1?)"

# cfl-idr's wrapper is Gradle 8.x, which does not run on JDK 25+: say so instead of a class file error.
JAVA_BIN="${JAVA_HOME:+$JAVA_HOME/bin/}java"
java_major="$("$JAVA_BIN" -XshowSettings:properties -version 2>&1 | sed -n 's/^ *java.specification.version = //p' | cut -d. -f1 || true)"
gradle_major="$(sed -n 's/^distributionUrl=.*gradle-\([0-9]*\)\..*/\1/p' "$SRC/gradle/wrapper/gradle-wrapper.properties")"
if [ -n "$java_major" ] && [ -n "$gradle_major" ] && [ "$gradle_major" -lt 9 ] && [ "$java_major" -ge 25 ]; then
    die "Gradle $gradle_major of cfl-idr needs JAVA_HOME with a JDK 17..24 (got $java_major), e.g. JAVA_HOME=\$HOME/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2"
fi

# Build ucfs-main against .ucfs/m2 and publish with cfl-idr's own wrapper, into .cflidr/m2 only.
echo "building cfl-idr @ $COMMIT against UCFS @ $UCFS_COMMIT, publishing org.cfl_idr_with_gll:cfl-idr-with-gll:$VERSION into $M2"
(cd "$SRC" && bash ./gradlew --console=plain -q --no-daemon -p ucfs-main \
    "-PucfsRepo=$UCFS_M2" "-PucfsVersion=$UCFS_VERSION" \
    publishLibPublicationToMavenLocal "-Dmaven.repo.local=$M2")

[ -f "$JAR" ] && [ -f "$POM" ] \
    || die "cfl-idr @ $COMMIT did not publish org.cfl_idr_with_gll:cfl-idr-with-gll:$VERSION into $M2 (does its version differ?)"
got="$(manifest_attr "$JAR" CflIdr-Commit)"
[ "$got" = "$COMMIT" ] || die "published cfl-idr has CflIdr-Commit '$got', expected cflidrCommit '$COMMIT'"
dirty="$(manifest_attr "$JAR" CflIdr-Dirty)"
[ "$dirty" = "false" ] || die "published cfl-idr has CflIdr-Dirty '$dirty', expected 'false'"
got="$(manifest_attr "$JAR" UCFS-Commit)"
[ "$got" = "$UCFS_COMMIT" ] || die "published cfl-idr has UCFS-Commit '$got', expected ucfsCommit '$UCFS_COMMIT'"
echo "cfl-idr org.cfl_idr_with_gll:cfl-idr-with-gll:$VERSION @ $COMMIT published into $M2"
