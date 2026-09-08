import java.io.FileOutputStream
import java.util.jar.JarEntry
import java.util.jar.JarOutputStream
import com.android.build.gradle.LibraryExtension
import org.gradle.api.tasks.compile.JavaCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library")) {
            // Keep legacy Flutter plugins aligned with the app. Several
            // otherwise compatible plugins still hard-code Android 33.
            extensions.configure<LibraryExtension> {
                compileSdkVersion(36)
            }
        }
    }
    project.evaluationDependsOn(":app")
    tasks.withType<JavaCompile>().configureEach {
        // Optional build-host workaround: some locked-down Windows hosts deny
        // zipfs real-path checks when Gradle closes a classpath JAR. Using the
        // command-line compiler lets a successful compilation remain successful.
        if (System.getenv("CLOUDREVE_FORCE_EXTERNAL_JAVAC") == "true") {
            options.isFork = true
            val javaHome = System.getenv("JAVA_HOME")
            if (!javaHome.isNullOrBlank()) {
                options.forkOptions.executable = file("$javaHome/bin/javac.exe").absolutePath
            }

            // The same host cannot safely expose Gradle-owned classpath entries
            // directly to javac. Mirror directories into JARs and copy existing
            // archives so javac never races Gradle's file handles.
            doFirst {
                val extraClasspath = temporaryDir.resolve("directory-classpath")
                extraClasspath.deleteRecursively()
                extraClasspath.mkdirs()
                val mirroredClasspath = classpath.files
                    .filter { it.exists() }
                    .mapIndexed { index, entry ->
                        if (entry.isDirectory) {
                            val jarFile = extraClasspath.resolve("classpath-$index.jar")
                            JarOutputStream(FileOutputStream(jarFile)).use { output ->
                                entry.walkTopDown()
                                    .filter { it.isFile }
                                    .forEach { source ->
                                        val name = source.relativeTo(entry).invariantSeparatorsPath
                                        output.putNextEntry(JarEntry(name))
                                        source.inputStream().use { it.copyTo(output) }
                                        output.closeEntry()
                                    }
                            }
                            jarFile
                        } else {
                            val suffix = entry.extension.ifBlank { "jar" }
                            entry.copyTo(
                                extraClasspath.resolve("classpath-$index.$suffix"),
                                overwrite = true,
                            )
                        }
                    }
                classpath = project.files(mirroredClasspath)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
