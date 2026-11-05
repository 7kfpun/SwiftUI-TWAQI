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
// Firebase config (gitignored). Without it the Firebase plugins stay off and FCM is not wired.
val hasGoogleServices = file("google-services.json").isFile

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
        // AdMob (FOX-58). The example file holds Google's test ids.
        manifestPlaceholders["ADMOB_APP_ID"] = secret("ADMOB_APP_ID")
        listOf(
            "AD_UNIT_ID_MAIN_FOOTER",
            "AD_UNIT_ID_DETAILS_LIST_FOOTER",
            "AD_UNIT_ID_DETAILS_FOOTER",
            "AD_UNIT_ID_FAVOURITES_FOOTER",
            "AD_UNIT_ID_HELP_FOOTER"
        ).forEach { buildConfigField("String", it, javaString(secret(it))) }
        // Push alerts (FOX-57): the push Worker's base URL (iOS: PushApiUrl). Empty: alerts are
        // saved on the phone and not synced. FCM is on only with app/google-services.json.
        buildConfigField("String", "PUSH_API_URL", javaString(secret("PUSH_API_URL")))
        buildConfigField("boolean", "FCM_ENABLED", hasGoogleServices.toString())
        manifestPlaceholders["FCM_ENABLED"] = hasGoogleServices.toString()
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

    testOptions {
        // android.util.Log and friends return defaults in JVM tests instead of throwing.
        unitTests.isReturnDefaultValues = true
    }

    // The in-app language picker (FOX-56) switches to a language the phone may not use, so
    // the bundle keeps every language in the base APK instead of splitting them by locale.
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

// Firebase (FOX-85: Crashlytics and Analytics, nothing else). The plugins need
// app/google-services.json, which is gitignored, so they apply only when it is
// there. Without it the app still builds and Firebase stays uninitialised.
if (hasGoogleServices) {
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
    implementation(libs.androidx.appcompat)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.play.billing)
    implementation(libs.play.services.ads)
    implementation(libs.google.ump)
    debugImplementation(libs.androidx.compose.ui.tooling)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)

    // Data layer (FOX-53): OkHttp for the AQI API and Directus, kotlinx.serialization's JSON tree
    // for tolerant parsing (no compiler plugin), coroutines for the repositories.
    implementation(libs.okhttp)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)

    // Station page location map (FOX-55); the key is MAPS_API_KEY in secrets.properties.
    implementation(libs.maps.compose)
    // Map tab (FOX-54): marker clustering, and the fold line for the wide layout.
    implementation(libs.maps.compose.utils)
    implementation(libs.androidx.window)

    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.analytics)
    implementation(libs.firebase.crashlytics)
    // FOX-57: FCM push alerts; the alert sync runs in WorkManager.
    implementation(libs.firebase.messaging)
    implementation(libs.androidx.work.runtime.ktx)

    testImplementation(libs.junit)
    testImplementation(libs.okhttp.mockwebserver)
    testImplementation(libs.kotlinx.coroutines.test)
}
