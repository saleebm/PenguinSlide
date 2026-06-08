plugins {
    kotlin("jvm")
    application
}

dependencies {
    val gdxVersion = "1.13.1"
    implementation(project(":core"))
    implementation("com.badlogicgames.gdx:gdx-backend-lwjgl3:$gdxVersion")
    implementation("com.badlogicgames.gdx:gdx-platform:$gdxVersion:natives-desktop")
    implementation("com.badlogicgames.gdx:gdx-freetype-platform:$gdxVersion:natives-desktop")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

application {
    mainClass.set("dev.copt.penguinslide.lwjgl3.Lwjgl3LauncherKt")
}

// libGDX desktop loads assets relative to the working directory.
tasks.named<JavaExec>("run") {
    workingDir = rootProject.file("assets")
    // macOS requires the GL window to spin up on the first thread.
    if (System.getProperty("os.name").lowercase().contains("mac")) {
        jvmArgs("-XstartOnFirstThread")
    }
    // Forward dev screenshot props (-Dps.screenshot=<s> -Dps.screenshotFile=<path>) to the app.
    System.getProperties().forEach { k, v ->
        if (k.toString().startsWith("ps.")) systemProperty(k.toString(), v.toString())
    }
}
