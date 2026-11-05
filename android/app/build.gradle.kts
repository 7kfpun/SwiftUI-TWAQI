import com.github.triplet.gradle.androidpublisher.ReleaseStatus
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.play.publisher)
    alias(libs.plugins.ktlint)
}

fun loadProperties(file: File): Properties = Properties().apply {
    if (file.isFile) file.inputStream().use(::load)
}

// App config. android/secrets.properties (gitignored) overrides
// android/secrets.example.properties key by key, so a clean checkout builds
// with the example values.
val exampleSecrets = loadProperties(rootProject.file("secrets.example.properties"))
val localSecrets = loadProperties(rootProject.file("secrets.properties"))

fun secret(name: String): String = localSecrets.getProperty(name) ?: exampleSecrets.getProperty(name, "")

fun javaString(value: String): String = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

// Release signing from android/keystore.properties (gitignored). Without it a
// release builds unsigned (app-release-unsigned.apk), and uploading to Play
// stops with a message.
val keystoreFile = rootProject.file("keystore.properties")
val keystore = loadProperties(keystoreFile)
val hasReleaseKeystore = keystoreFile.isFile
if (hasReleaseKeystore) {
    val missing = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .filter { keystore.getProperty(it).isNullOrBlank() }
    if (missing.isNotEmpty()) {
        throw GradleException(
            "android/keystore.properties is missing ${missing.joinToString()}. " +
                "See android/keystore.example.properties."
        )
    }
    if (!rootProject.file(keystore.getProperty("storeFile")).isFile) {
        throw GradleException(
            "android/keystore.properties: storeFile does not point to a file " +
                "(a relative path is resolved from android/)."
        )
    }
}
val uploadTask = Regex("(?i)(^|:)publish(\\w*(bundle|apk))?$")
val unsignedUploadMessage =
    "Uploading to Play needs a signed release: copy android/keystore.example.properties " +
        "to android/keystore.properties and fill it in (android/README.md, Release)."
// From the command line: stop before anything builds.
if (!hasReleaseKeystore && gradle.startParameter.taskNames.any { uploadTask.containsMatchIn(it) }) {
    throw GradleException(unsignedUploadMessage)
}
// Any other way in (an IDE run configuration, a dependent task): stop before
// the upload task's own action runs.
tasks.matching { uploadTask.containsMatchIn(it.name) }.configureEach {
    val signed = hasReleaseKeystore
    val message = unsignedUploadMessage
    doFirst { if (!signed) throw GradleException(message) }
}

android {
    namespace = "com.kfpun.twaqi"
    compileSdk = 36

    defaultConfig {
        // Same id as the old React Native app, so the Play listing updates in place.
        applicationId = "com.kfpun.twaqi"
        minSdk = 26
        targetSdk = 36
        // Always above 3000000 (the old app shipped codes up to 2097176) and increasing.
        versionCode = 3_000_000
        versionName = "2.0.0"

        buildConfigField("String", "API_DOMAIN", javaString(secret("API_DOMAIN")))
        buildConfigField("String", "DIRECTUS_URL", javaString(secret("DIRECTUS_URL")))
        buildConfigField("String", "DIRECTUS_FEEDBACK_TOKEN", javaString(secret("DIRECTUS_FEEDBACK_TOKEN")))
        buildConfigField("String", "DIRECTUS_COOPERATE_TOKEN", javaString(secret("DIRECTUS_COOPERATE_TOKEN")))
        manifestPlaceholders["MAPS_API_KEY"] = secret("MAPS_API_KEY")
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
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release") else null
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

    lint {
        abortOnError = true
        checkReleaseBuilds = true
    }
}

// Firebase (FOX-85: Crashlytics and Analytics, nothing else). The plugins need
// app/google-services.json, which is gitignored, so they apply only when it is
// there. Without it the app still builds and Firebase stays uninitialised.
if (file("google-services.json").isFile) {
    apply(plugin = libs.plugins.google.services.get().pluginId)
    apply(plugin = libs.plugins.firebase.crashlytics.get().pluginId)
}

// Play upload (Gradle Play Publisher) to the internal track, as a draft the
// user rolls out in Play Console. The service-account JSON is gitignored; its
// path comes from PLAY_SERVICE_ACCOUNT_JSON in secrets.properties.
play {
    track.set("internal")
    releaseStatus.set(ReleaseStatus.DRAFT)
    defaultToAppBundles.set(true)
    val credentials = rootProject.file(secret("PLAY_SERVICE_ACCOUNT_JSON").ifBlank { "play-service-account.json" })
    if (credentials.isFile) serviceAccountCredentials.set(credentials)
}

ktlint {
    version.set("1.8.0")
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    debugImplementation(libs.androidx.compose.ui.tooling)

    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.analytics)
    implementation(libs.firebase.crashlytics)

    testImplementation(libs.junit)
}
