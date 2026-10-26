#!/usr/bin/env bash
# E5 host setup: prepares a clean Ubuntu 24.04 machine (the VM of E5.md D7) for scripts/ucfs/e5-full.sh - the
# packages, the pinned Temurin JDKs 21 and 11 (sha256 checked before they are unpacked), an isolated Gradle home
# without daemons, a clone of this repository at the given commit with its submodules, UCFS (bootstrap.sh) and the
# fat jar of Qilin. The file is self-contained: it can be fetched alone (curl of the raw file) and run outside a
# clone. Contract: docs/ai/tickets/E5-S4.md (in the Diploma_work docs, not in this repository).
#
# Usage: bash scripts/ucfs/e5-vm-setup.sh <prefix> <commit>
#   <prefix>  the directory of the setup; it must not exist or be empty (one setup, one directory)
#   <commit>  the commit of this repository to check out, 40 hex digits
#   Exit 0 = ready. Exit 2 = wrong arguments (commit not 40 hex digits, <prefix> not empty), before anything is
#   done. Exit 3 = a problem of the environment, a download or the build, with a message on stderr.
#
# Environment:
#   E5_NO_APT     1: do not call apt-get, only check that the commands are there (default: install them with
#                 sudo apt-get; sudo is used for apt-get only)
#   E5_JDK_CACHE  a directory with JDK tarballs: any file *.tar.gz in it whose sha256 is a pinned one is used
#                 (the file is taken by its sha256, not by its name); default none
#   E5_OFFLINE    1: download nothing (a JDK must then be in E5_JDK_CACHE, else exit 3). The clone, the
#                 submodules and the Gradle build still need the network (or E5_REPO_URL a local path).
#   E5_REPO_URL   the repository to clone (default https://github.com/hse-se-team-2026/Qilin-AI-exp.git)
#
# Steps:
#   (a) without E5_NO_APT=1: sudo apt-get update and sudo apt-get install -y git python3 time unzip curl
#       ca-certificates xz-utils (each waits up to 600 s for the dpkg lock); then (always) a check of git
#       python3 /usr/bin/time unzip curl sha256sum tar xz and of pgrep lscpu timeout (procps, util-linux,
#       coreutils: e5-full.sh and its parts need them)
#   (b) the JDKs, pinned (URL of the GitHub release of Adoptium, sha256 = its .sha256.txt):
#         Temurin jdk-21.0.12.1+1  OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz
#                                  ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94
#         Temurin jdk-11.0.32.1+1  OpenJDK11U-jdk_x64_linux_hotspot_11.0.32.1_1.tar.gz
#                                  5c3f68887c325d36d852ba534303e1f5f1f5cae7d6cc1e951d73e0d8e98a058d
#       a tarball of E5_JDK_CACHE with the pinned sha256, else (not E5_OFFLINE=1) a download into <prefix>/jdks/
#       that is unpacked only when its sha256 is the pinned one; unpacked into <prefix>/jdks/, and each
#       <jdk>/bin/java -version must name its Temurin version
#   (c) GRADLE_USER_HOME=<prefix>/gradle-home with gradle.properties: both JDKs as the only installations, no
#       auto-detection, no auto-download (UCFS @ bd1c111 cannot download its JDK 11 itself), no Gradle daemon,
#       the Kotlin compiler in-process (no daemon left as a java process on the machine)
#   (d) git clone <E5_REPO_URL> <prefix>/Qilin-AI-exp, checkout --detach <commit>, submodules qilin.microben and
#       artifact/benchmarks (--depth 1)
#   (e) in the clone with JAVA_HOME=<jdk21>: bash scripts/ucfs/bootstrap.sh, gradlew build -x test, gradlew
#       fatJar -x test, git checkout -- artifact/Qilin-0.9.9-SNAPSHOT.jar (fatJar copies its jar over it), the
#       jar copied to <prefix>/jar/Qilin-fat.jar; then no process may still have <prefix>/gradle-home on its
#       command line (waits up to 30 s, else exit 3) and the clone must be clean (else exit 3)
#
# Files:
#   <prefix>/jdks/jdk-21.0.12.1+1, <prefix>/jdks/jdk-11.0.32.1+1   the JDKs (and the downloaded tarballs)
#   <prefix>/gradle-home/            the Gradle home of the build, gradle.properties as in (c)
#   <prefix>/Qilin-AI-exp/           the clone
#   <prefix>/jar/Qilin-fat.jar       the fat jar
#   <prefix>/bootstrap.log           output of bootstrap.sh
#   <prefix>/build.log               output of the two Gradle runs
#   <prefix>/setup.tsv               key value, in this order: repo-url commit git-head (git rev-parse HEAD of the
#                                    clone) tree-clean (yes when `git status --porcelain --untracked-files=no` of
#                                    the clone is empty) jdk21 jdk21-sha256 jdk11 jdk11-sha256 (directories and
#                                    tarball sha256) java-version (second line of <jdk21>/bin/java -version) jar
#                                    jar-sha256 started finished (date -Iseconds)
#
# Stdout: "e5-vm-setup: <step>" lines while it goes and, last,
#   e5-vm-setup: ready in <prefix as realpath>
#   e5-vm-setup: next: cd <clone> && JAVA_HOME=<jdk21> QILIN_JAR=<jar> bash scripts/ucfs/e5-full.sh <prefix>/results
# Contains no credentials, keys or addresses of machines.

set -u

NAME=e5-vm-setup
die2() { echo "$NAME: $*" >&2; exit 2; }
die3() { echo "$NAME: $*" >&2; exit 3; }
say() { echo "$NAME: $*"; }

JDK21_URL='https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz'
JDK21_FILE=OpenJDK21U-jdk_x64_linux_hotspot_21.0.12.1_1.tar.gz
JDK21_SHA=ce79869e1307ed8ee1e2baa86a412b1eb5b75d10a01006d788a6f968bcfaee94
JDK21_DIR=jdk-21.0.12.1+1
JDK21_VERSION=Temurin-21.0.12.1+1
JDK11_URL='https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.32.1%2B1/OpenJDK11U-jdk_x64_linux_hotspot_11.0.32.1_1.tar.gz'
JDK11_FILE=OpenJDK11U-jdk_x64_linux_hotspot_11.0.32.1_1.tar.gz
JDK11_SHA=5c3f68887c325d36d852ba534303e1f5f1f5cae7d6cc1e951d73e0d8e98a058d
JDK11_DIR=jdk-11.0.32.1+1
JDK11_VERSION=Temurin-11.0.32.1+1
COMMITTED_JAR=artifact/Qilin-0.9.9-SNAPSHOT.jar
BUILT_JAR=build/libs/Qilin-0.9.9-SNAPSHOT.jar

[ $# -eq 2 ] || die2 "usage: bash scripts/ucfs/e5-vm-setup.sh <prefix> <commit>"
PREFIX_ARG="$1"
COMMIT="$2"
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || die2 "commit must be 40 hex digits, got '$COMMIT'"
if [ -e "$PREFIX_ARG" ]; then
    [ -d "$PREFIX_ARG" ] && [ -z "$(ls -A -- "$PREFIX_ARG")" ] || die2 "$PREFIX_ARG exists and is not an empty directory"
fi
NO_APT="${E5_NO_APT:-0}"
OFFLINE="${E5_OFFLINE:-0}"
CACHE="${E5_JDK_CACHE:-}"
REPO_URL="${E5_REPO_URL:-https://github.com/hse-se-team-2026/Qilin-AI-exp.git}"
STARTED="$(date -Iseconds)"

# (a) packages
if [ "$NO_APT" != 1 ]; then
    say "installing packages with apt-get"
    # a fresh cloud image may still run unattended-upgrades: wait for the dpkg lock up to 10 min
    sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 update -q || die3 "apt-get update failed"
    sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 install -y -q git python3 time unzip curl \
        ca-certificates xz-utils || die3 "apt-get install failed"
fi
for c in git python3 unzip curl sha256sum tar xz pgrep lscpu timeout; do
    command -v "$c" > /dev/null || die3 "command $c not found"
done
[ -x /usr/bin/time ] || die3 "GNU time /usr/bin/time not found (package time)"

mkdir -p "$PREFIX_ARG" || die3 "cannot create $PREFIX_ARG"
PREFIX="$(realpath "$PREFIX_ARG")"
JDKS="$PREFIX/jdks"
GHOME="$PREFIX/gradle-home"
CLONE="$PREFIX/Qilin-AI-exp"
JARDIR="$PREFIX/jar"
JAR="$JARDIR/Qilin-fat.jar"
mkdir -p "$JDKS" || die3 "cannot create $JDKS"

# (b) JDKs. sha256 of every candidate file, each file hashed once
declare -A SHA_OF=()
sha_of() {
    [ -n "${SHA_OF[$1]+x}" ] || SHA_OF[$1]="$(sha256sum -- "$1" | cut -d' ' -f1)"
    printf '%s' "${SHA_OF[$1]}"
}

# tarball <file name> <url> <sha256> -> the path of a tarball with this sha256 (cache, else download)
TARBALL=""
tarball() {
    local file="$1" url="$2" sha="$3" f part
    TARBALL=""
    if [ -n "$CACHE" ] && [ -d "$CACHE" ]; then
        # the file of the release name first (one hash in the usual case), then any other *.tar.gz
        for f in "$CACHE/$file" "$CACHE"/*.tar.gz; do
            [ -f "$f" ] || continue
            if [ "$(sha_of "$f")" = "$sha" ]; then
                TARBALL="$f"
                return 0
            fi
        done
    fi
    [ "$OFFLINE" != 1 ] || die3 "E5_OFFLINE=1 and no tarball with sha256 $sha in E5_JDK_CACHE='$CACHE'"
    part="$JDKS/$file.part"
    say "downloading $url"
    curl -fsSL --proto '=https' --retry 3 -o "$part" "$url" || { rm -f -- "$part"; die3 "download of $url failed"; }
    f="$(sha256sum -- "$part" | cut -d' ' -f1)"
    if [ "$f" != "$sha" ]; then
        rm -f -- "$part"
        die3 "$url has sha256 $f, pinned $sha"
    fi
    mv -- "$part" "$JDKS/$file" || die3 "cannot move $part"
    TARBALL="$JDKS/$file"
}

# unpack <tarball> <directory name> <version> -> the JDK in $JDKS/<directory name>, checked
unpack() {
    local t="$1" dir="$JDKS/$2" v
    rm -rf -- "$dir"
    tar -xzf "$t" -C "$JDKS" || die3 "cannot unpack $t"
    [ -x "$dir/bin/java" ] || die3 "$t has no $2/bin/java"
    v="$("$dir/bin/java" -version 2>&1 | sed -n 2p)"
    case "$v" in
        *"$3"*) ;;
        *) die3 "$dir/bin/java -version says '$v', expected $3" ;;
    esac
}

tarball "$JDK21_FILE" "$JDK21_URL" "$JDK21_SHA"
T21="$TARBALL"
tarball "$JDK11_FILE" "$JDK11_URL" "$JDK11_SHA"
T11="$TARBALL"
say "unpacking $T21 and $T11 into $JDKS"
unpack "$T21" "$JDK21_DIR" "$JDK21_VERSION"
unpack "$T11" "$JDK11_DIR" "$JDK11_VERSION"
J21="$JDKS/$JDK21_DIR"
J11="$JDKS/$JDK11_DIR"

# (c) isolated Gradle home
mkdir -p "$GHOME" || die3 "cannot create $GHOME"
cat > "$GHOME/gradle.properties" <<EOF
org.gradle.java.installations.paths=$J11,$J21
org.gradle.java.installations.auto-detect=false
org.gradle.java.installations.auto-download=false
org.gradle.daemon=false
kotlin.compiler.execution.strategy=in-process
EOF
export GRADLE_USER_HOME="$GHOME"

# (d) clone
say "cloning $REPO_URL into $CLONE at $COMMIT"
git clone -q -- "$REPO_URL" "$CLONE" || die3 "git clone $REPO_URL failed"
git -C "$CLONE" -c advice.detachedHead=false checkout -q --detach "$COMMIT" || die3 "commit $COMMIT not in $REPO_URL"
say "submodules qilin.microben and artifact/benchmarks"
git -C "$CLONE" submodule update -q --init qilin.microben || die3 "submodule qilin.microben failed"
git -C "$CLONE" submodule update -q --init --depth 1 artifact/benchmarks || die3 "submodule artifact/benchmarks failed"

# (e) UCFS and the fat jar
say "bootstrap.sh (UCFS), log $PREFIX/bootstrap.log"
(cd "$CLONE" && JAVA_HOME="$J21" bash scripts/ucfs/bootstrap.sh) > "$PREFIX/bootstrap.log" 2>&1 \
    || die3 "bootstrap.sh failed (see $PREFIX/bootstrap.log)"
say "gradlew build -x test, gradlew fatJar -x test, log $PREFIX/build.log"
(cd "$CLONE" && JAVA_HOME="$J21" bash ./gradlew --console=plain --no-daemon build -x test \
    && JAVA_HOME="$J21" bash ./gradlew --console=plain --no-daemon fatJar -x test) > "$PREFIX/build.log" 2>&1
rc=$?
git -C "$CLONE" checkout -q -- "$COMMITTED_JAR" || die3 "cannot restore $COMMITTED_JAR in the clone"
[ $rc -eq 0 ] && [ -f "$CLONE/$BUILT_JAR" ] || die3 "the Gradle build failed, exit $rc (see $PREFIX/build.log)"
mkdir -p "$JARDIR" && cp -- "$CLONE/$BUILT_JAR" "$JAR" || die3 "cannot copy the jar to $JAR"

left=""
for _ in $(seq 30); do
    left="$(pgrep -f -- "$GHOME" || true)"
    [ -n "$left" ] || break
    sleep 1
done
[ -z "$left" ] || die3 "processes with $GHOME still run after the build: $(echo $left)"

GIT_HEAD="$(git -C "$CLONE" rev-parse HEAD)"
if [ -z "$(git -C "$CLONE" status --porcelain --untracked-files=no)" ]; then
    TREE_CLEAN=yes
else
    TREE_CLEAN=no
fi
{
    printf 'key\tvalue\n'
    printf 'repo-url\t%s\n' "$REPO_URL"
    printf 'commit\t%s\n' "$COMMIT"
    printf 'git-head\t%s\n' "$GIT_HEAD"
    printf 'tree-clean\t%s\n' "$TREE_CLEAN"
    printf 'jdk21\t%s\n' "$J21"
    printf 'jdk21-sha256\t%s\n' "$(sha_of "$T21")"
    printf 'jdk11\t%s\n' "$J11"
    printf 'jdk11-sha256\t%s\n' "$(sha_of "$T11")"
    printf 'java-version\t%s\n' "$("$J21/bin/java" -version 2>&1 | sed -n 2p)"
    printf 'jar\t%s\n' "$JAR"
    printf 'jar-sha256\t%s\n' "$(sha256sum -- "$JAR" | cut -d' ' -f1)"
    printf 'started\t%s\n' "$STARTED"
    printf 'finished\t%s\n' "$(date -Iseconds)"
} > "$PREFIX/setup.tsv"
[ "$GIT_HEAD" = "$COMMIT" ] || die3 "the clone is at $GIT_HEAD, not $COMMIT"
[ "$TREE_CLEAN" = yes ] || die3 "the clone has changes to tracked files after the build: $(git -C "$CLONE" status --porcelain --untracked-files=no | head -n 3 | tr '\n' ' ')"

say "ready in $PREFIX"
say "next: cd $CLONE && JAVA_HOME=$J21 QILIN_JAR=$JAR bash scripts/ucfs/e5-full.sh $PREFIX/results"
