#!/usr/bin/env bash
# Builds UCFS (UCFS-AI-dev) at the commit pinned in gradle.properties and publishes
# org.ucfs:solver:<ucfsVersion> into the project-local Maven repository .ucfs/m2,
# which qilin.pta/build.gradle reads. Nothing is written outside .ucfs/ (not to ~/.m2).
#
#   gradle.properties: ucfsVersion, ucfsCommit, ucfsGitUrl
#   UCFS_SRC=<git URL | path>   take the UCFS sources from here instead of ucfsGitUrl
#                               (must contain ucfsCommit)
#   .ucfs/src                   UCFS checkout (detached at ucfsCommit)
#   .ucfs/m2                    Maven repository with org.ucfs:solver
#
# UCFS is built by its own Gradle wrapper (Gradle 9) in a separate process. It needs JDK 17+
# in JAVA_HOME (or on PATH) to run Gradle and a JDK 11 for the UCFS toolchain.
# If .ucfs/m2 already has the solver jar built from ucfsCommit, nothing is rebuilt.
# Usage: bash scripts/ucfs/bootstrap.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROPS="$ROOT/gradle.properties"

die() { echo "bootstrap.sh: $*" >&2; exit 1; }
prop() { sed -n "s/^$1=//p" "$PROPS" | tail -n 1 | tr -d '\r'; }
# manifest_attr <jar> <name> -> value of a jar manifest attribute (empty if absent)
manifest_attr() { unzip -p "$1" META-INF/MANIFEST.MF | tr -d '\r' | sed -n "s/^$2: //p"; }

command -v git >/dev/null || die "git is required"
command -v unzip >/dev/null || die "unzip is required"

VERSION="$(prop ucfsVersion)"
COMMIT="$(prop ucfsCommit)"
SRC_URL="${UCFS_SRC:-$(prop ucfsGitUrl)}"
[ -n "$VERSION" ] || die "no ucfsVersion in $PROPS"
echo "$COMMIT" | grep -qxE '[0-9a-f]{40}' || die "ucfsCommit in $PROPS is not a 40-hex commit: '$COMMIT'"
[ -n "$SRC_URL" ] || die "no ucfsGitUrl in $PROPS (and UCFS_SRC is not set)"

DIR="$ROOT/.ucfs"
SRC="$DIR/src"
M2="$DIR/m2"
JAR="$M2/org/ucfs/solver/$VERSION/solver-$VERSION.jar"
POM="$M2/org/ucfs/solver/$VERSION/solver-$VERSION.pom"

# Already published from the pinned commit: nothing to do.
if [ -f "$JAR" ] && [ -f "$POM" ] \
    && [ "$(manifest_attr "$JAR" UCFS-Commit)" = "$COMMIT" ] \
    && [ "$(manifest_attr "$JAR" UCFS-Dirty)" = "false" ]; then
    echo "UCFS org.ucfs:solver:$VERSION @ $COMMIT is already in $M2 (nothing to do)"
    exit 0
fi

# Sources: clone once, then reuse .ucfs/src and fetch the pinned commit if it is missing.
mkdir -p "$DIR"
if [ ! -d "$SRC/.git" ]; then
    rm -rf "$SRC"   # leftover of an interrupted clone (only inside .ucfs/)
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
# Do not silently throw away edits someone made in .ucfs/src. A --no-checkout clone has no
# index yet (every file would look deleted), so only an existing checkout is checked.
if [ -f "$SRC/.git/index" ] && [ -n "$(git -C "$SRC" status --porcelain --untracked-files=no)" ]; then
    die "$SRC has local changes to tracked files; save them elsewhere or delete $SRC"
fi
git -C "$SRC" -c advice.detachedHead=false checkout -q --detach "$COMMIT"

# Build and publish with UCFS's own wrapper, into .ucfs/m2 only.
echo "building UCFS @ $COMMIT and publishing org.ucfs:solver:$VERSION into $M2"
(cd "$SRC" && bash ./gradlew --console=plain -q publishSolverPublicationToMavenLocal "-Dmaven.repo.local=$M2")

[ -f "$JAR" ] && [ -f "$POM" ] \
    || die "UCFS @ $COMMIT did not publish org.ucfs:solver:$VERSION into $M2 (does its ucfsVersion differ?)"
got="$(manifest_attr "$JAR" UCFS-Commit)"
[ "$got" = "$COMMIT" ] || die "published solver has UCFS-Commit '$got', expected ucfsCommit '$COMMIT'"
dirty="$(manifest_attr "$JAR" UCFS-Dirty)"
[ "$dirty" = "false" ] || die "published solver has UCFS-Dirty '$dirty', expected 'false'"
echo "UCFS org.ucfs:solver:$VERSION @ $COMMIT published into $M2"
