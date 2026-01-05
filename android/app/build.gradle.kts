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
            abiFilters += listOf("arm64-v8a")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
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
    // Use standard implementation for the android-arm64 specific jar
    // This contains the .so files in its resources
    implementation("org.bytedeco:ffmpeg:5.1.2-1.5.8:android-arm64") 
    
    // Keep this configuration for the extractor task below
    add("javacpp", "org.bytedeco:ffmpeg:5.1.2-1.5.8:android-arm64")
}

// ================= JAVACPP EXTRACT =================

val javacppExtract by tasks.registering(Copy::class) {
    dependsOn(configurations.getByName("javacpp"))
    
    // 1. Get the JARs from the configuration
    from(configurations.getByName("javacpp").map { zipTree(it) })
    
    // 2. Only include the android-arm64 native libraries
    include("lib/android-arm64/**")
    includeEmptyDirs = false

    // 3. FLATTEN/RENAME the path: 
    // This strips "lib/android-arm64/" from the path so the files land directly in our target
    eachFile {
        path = name 
    }

    // 4. Put them where Android expects 64-bit libs: "arm64-v8a"
    into("$buildDir/javacpp/jniLibs/arm64-v8a/")
}

// Force preBuild to depend on extraction
tasks.named("preBuild") {
    dependsOn(javacppExtract)
}

// Add the parent folder of "arm64-v8a" to jniLibs
android.sourceSets["main"].jniLibs.srcDirs("$buildDir/javacpp/jniLibs/")

flutter {
    source = "../.."
}
