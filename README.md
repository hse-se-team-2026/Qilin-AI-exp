[![Gradle](https://github.com/QilinPTA/Qilin/actions/workflows/gradle.yml/badge.svg?event=push)](https://github.com/QilinPTA/Qilin/actions/workflows/gradle.yml)
[![Docker](https://github.com/QilinPTA/Qilin/actions/workflows/docker-image.yml/badge.svg?event=push)](https://github.com/QilinPTA/Qilin/actions/workflows/docker-image.yml)
[![Gitpod Ready-to-Code](https://img.shields.io/badge/Gitpod-Ready--to--Code-blue?logo=gitpod)](https://gitpod.io/#https://github.com/QilinPTA/Qilin)

> :warning: [Documentation for Qilin](https://qilinpta.github.io/) is under development.

# News
* <b>[Moon](https://dl.acm.org/doi/10.1145/3763111) , another context debloating technique published in OOPSLA 2025, is now available in Qilin </b>
* <b>[DebloaterX](https://github.com/DongjieHe/DebloaterX) published in
  our [OOPSLA paper](https://dongjiehe.github.io/mypaper/OOPSLA2023_DebloaterX_Preprint.pdf) is now available in
  Qilin</b>
* <b>Qilin now supports Soot-4.7.1</b>

# Qilin: A fully imperative Java Pointer Analysis Framework.

The repository hosts Qilin, a new Java pointer analysis framework for supporting fine-grained context-sensitivity. For
technical details, please refer to
our [ECOOP'22 paper](https://drops.dagstuhl.de/entities/document/10.4230/LIPIcs.ECOOP.2022.30).

## A Quick Start

### Prerequisites

* Java 16+ (Qilin uses the pattern matching for `instanceof` provided since Java 16).
* Python 3.5+ (the api `subprocess.run` used in `artifact/qilin.py` is added in Python 3.5).

### Download

This repository contains a `submodule` that contains a set of real-world ready-to-use benchmarks for Qilin.
If you want to run Qilin on these benchmarks, please use the following command to fetch the Qilin source code:

```
$ git clone --recurse-submodules https://github.com/QilinPTA/Qilin.git
```

If you have cloned Qilin in a normal way, you still can use the command below to download these benchmarks:

```
$ git submodule update --init
```

### UCFS dependency (one-time bootstrap)

The `qilin.pta` tests use the [UCFS](https://github.com/UsatovPavel/UCFS-AI-dev) CFL-reachability
solver (`org.ucfs:solver`). It is not on Maven Central, so after cloning run the bootstrap script once:
it clones UCFS-AI-dev at the commit pinned in `gradle.properties` (`ucfsCommit`), builds it with its
own Gradle wrapper and publishes it into the project-local Maven repository `.ucfs/m2` (git-ignored;
`~/.m2` is not touched). The second command checks that Qilin resolves and calls the solver.
`JAVA_HOME` must point to a JDK 17+ (Qilin builds with a JDK 21 toolchain; UCFS needs a JDK 11 toolchain,
which Gradle looks up in the usual places, e.g. `~/.gradle/jdks`).

<!-- ucfs-bootstrap:begin -->
```
$ bash scripts/ucfs/bootstrap.sh
$ bash scripts/cflidr/bootstrap.sh
$ ./gradlew :qilin.pta:test --tests qilin.test.ucfs.UcfsDependencySmokeTest
```
<!-- ucfs-bootstrap:end -->

Running the script again does nothing if `.ucfs/m2` already holds the solver built from `ucfsCommit`.
`UCFS_SRC=<git URL or path>` takes the UCFS sources from somewhere else (it must contain `ucfsCommit`),
and `-PucfsRepo=<dir>` makes Gradle read UCFS from another Maven repository instead of `.ucfs/m2`.
To move to a newer UCFS, change `ucfsCommit` (and `ucfsVersion` if it changed) and rerun the script.

`bash scripts/cflidr/bootstrap.sh` does the same for the interleaved Dyck reachability library [cfl-idr-with-gll](https://github.com/hse-se-team-2026/cfl-idr-with-gll-AI-exp) used by `qilin.ucfs`: it builds `ucfs-main/` at `cflidrCommit` of `scripts/cflidr/cflidr.properties` against the UCFS in `.ucfs/m2` (one UCFS on the class path) and publishes it into `.cflidr/m2` (`CFLIDR_SRC=<git URL or path>`, `-PcflidrRepo=<dir>` as for UCFS; its Gradle 8.14 wrapper needs `JAVA_HOME` with a JDK 17..24).

### Building Qilin with Gradle

We use Gradle as the build automation tool. To build Qilin, use

```
$ ./run.sh
```

This script contains commands to generate `Qilin-VERSION-SNAPSHOT.jar`, which will be automatically moved
into `artifact/`.
The jar includes the Kotlin module `qilin.ucfs` and the UCFS solver, so building it (and compiling `qilin.pta`)
needs the bootstrap first: `bash scripts/ucfs/bootstrap.sh` and `bash scripts/cflidr/bootstrap.sh` (see above).

For users who want to build Qilin in IDE, please refer
to [this page](https://github.com/QilinPTA/Qilin/wiki/Set-up-the-Debugging-Environment-for-Qilin-in-IntelliJ-IDEA).

### Using Qilin

You can use Qilin either through its command-line interface (e.g., `driver.Main`) or as a library.
For researchers who are working on Java pointer analysis, we have provided a whole set of scripts, benchmarks (
e.g., `DaCapo2006`) and jdk libraries under `artifact/`.

To test Qilin, you can directly do:

```
$ cd artifact
$ python3 run.py antlr ci -print
```

The above command will analyse `antlr` with a context-insensitive pointer analysis with some metrics being displayed on
the screen.  
We plan to optimise the `run.py` script to make its help info more user-friendly.

## Documentation

| About Qilin                                                                                                                                                                   |                                                  Setup  Guide                                                   |                                                                                                                                                                                                               User Guide |                                                                                                                                                                                                                                                                                                  Developer Guide |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|:---------------------------------------------------------------------------------------------------------------:|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------:|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------:|
| Introducing Qilin -- [what it does](https://qilinpta.github.io/Qilin/#what-is-qilin) and [how we design it](https://github.com/QilinPTA/Qilin/wiki/Qilin-Design#qilin-design) | A step by step [setup guide](https://github.com/QilinPTA/Qilin/wiki/Setup-Guide#getting-started) to build Qilin | [Command-line options](https://github.com/QilinPTA/Qilin/wiki/Full-list-of-Qilin-options) of Qilin, and running Qilin with [an example](https://github.com/QilinPTA/Qilin/wiki/Analyse-a-Simple-Java-Program#an-example) | Detailed [technical documentation](https://qilinpta.github.io/Qilin/QilinCodeStructure.html) and how to [use Qilin as a lib](https://github.com/QilinPTA/Qilin/wiki/Qilin-as-a-lib) for your tool or [write your own analyses](https://github.com/QilinPTA/Qilin/wiki/Write-your-own-analysis-in-Qilin) in Qilin |

## Contributing to Qilin

Contributions are always welcome. Qilin is an open-source project that we publish in the hope that it will be useful to
the research community as a whole.
If you have a new feature or a bug fix that you would like to see in the official code repository, please open a merge
request here on Github and leave a short description of what you have done.

## License

Qilin is licenced under the GPL v2.1 license, see the LICENSE file.

