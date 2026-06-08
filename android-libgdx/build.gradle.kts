plugins {
    kotlin("jvm") version "2.1.0" apply false
    kotlin("android") version "2.1.0" apply false
    id("com.android.application") version "8.7.3" apply false
}

subprojects {
    repositories {
        mavenCentral()
        google()
        maven { url = uri("https://oss.sonatype.org/content/repositories/snapshots/") }
    }
}
