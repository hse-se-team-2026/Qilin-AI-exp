plugins {
	kotlin("jvm") version "2.4.0"
	application
}
val ucfsRepo: String by project
val cflidrSrc: String by project
repositories {
	exclusiveContent {
		forRepository { maven { url = uri(ucfsRepo) } }
		filter { includeGroup("org.ucfs") }
	}
	mavenCentral()
}
dependencies {
	implementation("org.ucfs:solver:0.1.0-ai-SNAPSHOT") { exclude(group = "ch.qos.logback") }
	implementation("org.antlr:antlr4:4.13.1")
	implementation("org.jgrapht:jgrapht-core:1.5.2")
}
sourceSets { main { kotlin.srcDir("$cflidrSrc/src/main/kotlin") } }
kotlin { jvmToolchain(21) }
application { mainClass.set("org.cfl_idr_with_gll.Main") }
tasks.register<Copy>("deps") { from(configurations.runtimeClasspath); into(layout.buildDirectory.dir("deps")) }
