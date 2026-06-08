pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
        google()
    }
}

rootProject.name = "PenguinSlide"

include(":core", ":lwjgl3", ":android")
