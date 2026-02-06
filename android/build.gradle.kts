// 1. ADD THIS BLOCK AT THE VERY TOP
buildscript {
    repositories {
        maven { url = uri("https://storage.googleapis.com/r8-releases/raw") }
    }
    dependencies {
        // This forces a newer version of the R8 compiler
        classpath("com.android.tools:r8:8.3.37")
    }
}

// 2. YOUR EXISTING CODE STARTS HERE
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
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}