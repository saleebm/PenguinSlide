pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
        google()
    }
}

// Lets Gradle auto-download a matching JDK for the Java 17 toolchains the modules request,
// so the build works on any machine without a hardcoded JDK path (see gradle.properties).
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "0.8.0"
}

rootProject.name = "PenguinSlide"

include(":core", ":lwjgl3", ":android")
