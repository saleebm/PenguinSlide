plugins {
    id("com.android.application")
    kotlin("android")
}

val gdxVersion = "1.13.1"

android {
    namespace = "dev.copt.penguinslide.android"
    compileSdk = 34
    buildToolsVersion = "34.0.0"

    sourceSets.named("main") {
        // Share the single asset root with desktop; native .so files land in libs/.
        assets.srcDir(rootProject.file("assets"))
        jniLibs.srcDir("libs")
    }

    defaultConfig {
        applicationId = "dev.copt.PenguinSlide"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.3.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        named("release") { isMinifyEnabled = false }
    }

    packaging {
        resources.excludes.add("META-INF/robovm/ios/robovm.xml")
    }
}

// Pin Java 17 via a toolchain so Gradle resolves/downloads the right JDK on any host
// (AGP does not support JDK 23). Sets the compile JDK and Kotlin jvmTarget to 17.
kotlin {
    jvmToolchain(17)
}

// libGDX native libraries are shipped as per-ABI jars; extract their .so into libs/<abi>
// so AGP packages them as jniLibs.
val natives: Configuration by configurations.creating

dependencies {
    implementation(project(":core"))
    implementation("com.badlogicgames.gdx:gdx-backend-android:$gdxVersion")
    implementation("com.badlogicgames.gdx:gdx-freetype:$gdxVersion")

    val abis = listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
    abis.forEach { abi ->
        natives("com.badlogicgames.gdx:gdx-platform:$gdxVersion:natives-$abi")
        natives("com.badlogicgames.gdx:gdx-freetype-platform:$gdxVersion:natives-$abi")
    }
}

tasks.register("copyAndroidNatives") {
    doFirst {
        natives.files.forEach { jar ->
            // jar name looks like gdx-platform-1.13.1-natives-arm64-v8a.jar
            val abi = jar.name.substringAfter("natives-").substringBefore(".jar")
            val outDir = file("libs/$abi")
            outDir.mkdirs()
            copy {
                from(zipTree(jar))
                into(outDir)
                include("*.so")
            }
        }
    }
}

// Ensure natives are extracted before any APK packaging / merge step.
tasks.configureEach {
    if (name.contains("merge", ignoreCase = true) && name.contains("JniLibFolders", ignoreCase = true)) {
        dependsOn("copyAndroidNatives")
    }
    if (name.startsWith("package") || name.startsWith("assemble")) {
        dependsOn("copyAndroidNatives")
    }
}
