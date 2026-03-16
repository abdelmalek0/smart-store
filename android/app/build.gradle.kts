import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ================= JavaCPP CONFIG =================
configurations {
    create("javacpp")
}

android {
    namespace = "com.example.smart_store_linux"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.smart_store_linux"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            // arm64-v8a  = physical devices (RK3588, Pixel, etc.)
            // x86_64     = Android emulator on x86_64 host
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }

        resources {
            excludes += setOf(
                "META-INF/native-image/**",
                "META-INF/*.kotlin_module"
            )

            pickFirsts += setOf(
                "lib/**",
                "**/reflect-config.json",
                "**/jni-config.json"
            )
        }
    }
}

dependencies {
    implementation("org.bytedeco:javacv:1.5.8")
    // arm64-v8a  – physical ARM devices
    implementation("org.bytedeco:ffmpeg:5.1.2-1.5.8:android-arm64")
    add("javacpp", "org.bytedeco:ffmpeg:5.1.2-1.5.8:android-arm64")
    // x86_64     – Android emulator
    implementation("org.bytedeco:ffmpeg:5.1.2-1.5.8:android-x86_64")
    add("javacpp", "org.bytedeco:ffmpeg:5.1.2-1.5.8:android-x86_64")
}

// ================= JAVACPP EXTRACT =================

val javacppExtract by tasks.registering(Copy::class) {
    dependsOn(configurations.getByName("javacpp"))
    from(configurations.getByName("javacpp").map { zipTree(it) })
    // Extract both ABI variants from the javacpp jars
    include("lib/android-arm64/**", "lib/android-x86_64/**")
    includeEmptyDirs = false

    eachFile {
        // Remap  lib/android-arm64/libfoo.so  →  arm64-v8a/libfoo.so
        //        lib/android-x86_64/libfoo.so →  x86_64/libfoo.so
        val parts = relativePath.segments
        if (parts.size >= 2) {
            val abi = when (parts[1]) {
                "android-arm64"  -> "arm64-v8a"
                "android-x86_64" -> "x86_64"
                else             -> parts[1]
            }
            path = "$abi/${parts.last()}"
        } else {
            path = name
        }
    }

    into(layout.buildDirectory.dir("javacpp/jniLibs"))
}

tasks.named("preBuild") {
    dependsOn(javacppExtract)
}

// Fixed: Replaced deprecated $buildDir
android.sourceSets["main"].jniLibs.srcDirs(layout.buildDirectory.dir("javacpp/jniLibs"))

flutter {
    source = "../.."
}