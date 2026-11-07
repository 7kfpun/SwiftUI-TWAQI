import java.util.Properties

// The Wear OS app (FOX-62): the watch app, its complication and its tile. Same application id
// as the phone app, as Play requires for a Wear OS app in the same listing and the Data Layer
// requires to pair them, with its own versionCode range (android/README.md, Wear OS).
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ktlint)
}

fun loadProperties(file: File): Properties = Properties().apply {
    if (file.isFile) file.inputStream().use(::load)
}

// The same config files as :app: secrets.properties (gitignored) over the example, key by key.
val exampleSecrets = loadProperties(rootProject.file("secrets.example.properties"))
val localSecrets = loadProperties(rootProject.file("secrets.properties"))

fun secret(name: String): String = localSecrets.getProperty(name) ?: exampleSecrets.getProperty(name, "")

fun javaString(value: String): String = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

// Release signing from the same android/keystore.properties as :app (gitignored). The Data Layer
// only pairs the watch app with a phone app signed with the same key. Without it a release builds
// unsigned; :app's checks already explain a broken keystore.properties.
val keystoreFile = rootProject.file("keystore.properties")
val keystore = loadProperties(keystoreFile)
val hasReleaseKeystore = keystoreFile.isFile &&
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword").none { keystore.getProperty(it).isNullOrBlank() } &&
    rootProject.file(keystore.getProperty("storeFile")).isFile

android {
    namespace = "com.kfpun.twaqi.watch"
    compileSdk = 36

    defaultConfig {
        // Must match the phone app: Play and the Wearable Data Layer pair the two by it.
        applicationId = "com.kfpun.twaqi"
        // Wear OS 3 and later.
        minSdk = 30
        targetSdk = 36
        // Wear OS codes: 203_000_000 and up, always above the phone's (3_000_000 and up) and
        // increasing with every Wear OS upload. WearIdentityTest guards the range.
        versionCode = 203_000_001
        versionName = "2.0.1"

        buildConfigField("String", "API_DOMAIN", javaString(secret("API_DOMAIN")))
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystore.getProperty("storeFile"))
                storePassword = keystore.getProperty("storePassword")
                keyAlias = keystore.getProperty("keyAlias")
                keyPassword = keystore.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release") else null
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    // The phone app's language can differ from the watch's (FOX-56), so every language stays in the base APK.
    bundle {
        language {
            enableSplit = false
        }
    }

    lint {
        abortOnError = true
        checkReleaseBuilds = true
    }
}

ktlint {
    version.set("1.8.0")
}

dependencies {
    implementation(project(":core"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.fragment)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    debugImplementation(libs.androidx.compose.ui.tooling)

    // Compose for Wear OS, the complication and the tile.
    implementation(libs.wear.compose.material3)
    implementation(libs.wear.compose.foundation)
    implementation(libs.wear.compose.navigation)
    implementation(libs.wear.complications.data.source.ktx)
    implementation(libs.wear.tiles)
    implementation(libs.wear.protolayout)
    implementation(libs.androidx.concurrent.futures.ktx)
    // The station search's text input, and "Subscribe on your phone".
    implementation(libs.wear.input)
    implementation(libs.wear.remote.interactions)
    // The phone's favourites, Pro and language; the locked-complication events back.
    implementation(libs.play.services.wearable)

    // The API, standalone (iOS WatchAPI).
    implementation(libs.okhttp)
    implementation(libs.kotlinx.coroutines.android)

    testImplementation(libs.junit)
    testImplementation(libs.okhttp.mockwebserver)
    testImplementation(libs.kotlinx.coroutines.test)
}
