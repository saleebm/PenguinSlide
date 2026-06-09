plugins {
    kotlin("jvm")
}

dependencies {
    val gdxVersion = "1.13.1"
    api("com.badlogicgames.gdx:gdx:$gdxVersion")
    api("com.badlogicgames.gdx:gdx-freetype:$gdxVersion")

    testImplementation("org.junit.jupiter:junit-jupiter:5.11.3")
}

// Pin Java 17 via a toolchain so Gradle resolves/downloads the right JDK on any host
// (AGP rejects JDK 23). Sets both the compile JDK and Kotlin's jvmTarget to 17.
java {
    toolchain { languageVersion = JavaLanguageVersion.of(17) }
}

kotlin {
    jvmToolchain(17)
}

tasks.test {
    useJUnitPlatform()
}
