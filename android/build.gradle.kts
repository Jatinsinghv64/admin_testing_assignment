// android/build.gradle.kts
buildscript { // Add this buildscript block
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Replace with your current Android Gradle Plugin version
        // For example, if your app/build.gradle.kts uses compileSdk = flutter.compileSdkVersion,
        // you might be on a newer version like 8.x.x or 7.x.x
        classpath("com.android.tools.build:gradle:7.3.0") // <--- IMPORTANT: Adjust this version if needed.
        classpath("com.google.gms:google-services:4.4.1")
    // <--- ADD THIS LINE (use the latest stable version)
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
