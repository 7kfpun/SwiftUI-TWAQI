// Code the phone app (:app) and the Wear OS app (:wear) share (FOX-62): the indices and their
// level bands and colours, Taiwan time, and the phone ↔ watch Data Layer contract. Pure Kotlin
// with no resources, so either app can show it in its own strings.
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.ktlint)
}

android {
    namespace = "com.kfpun.twaqi.core"
    compileSdk = 36

    defaultConfig {
        // The phone app's minSdk; the watch app's is higher.
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        abortOnError = true
    }
}

ktlint {
    version.set("1.8.0")
}

dependencies {
    // The Data Layer payloads are JSON text, read with the JSON tree as the API is (no compiler plugin).
    api(libs.kotlinx.serialization.json)

    testImplementation(libs.junit)
}
