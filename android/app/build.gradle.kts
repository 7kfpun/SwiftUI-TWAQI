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
// AdMob (FOX-58, FOX-61). Debug builds always use Google's published test ids
// (developers.google.com/admob/android/test-ads), so a debug build on a real phone never
// serves real ads, and taps on them never count. Release builds use the real ids from
// secrets.properties, and verifyReleaseAdIds stops a release from packaging with test,
// placeholder or malformed ids.
val adMobTestPublisher = "ca-app-pub-3940256099942544"
val adMobTestAppId = "$adMobTestPublisher~3347511713"
val adMobTestBannerUnitId = "$adMobTestPublisher/6300978111"
val adUnitKeys = listOf(
    "AD_UNIT_ID_MAIN_FOOTER",
    "AD_UNIT_ID_DETAILS_LIST_FOOTER",
    "AD_UNIT_ID_DETAILS_FOOTER",
    "AD_UNIT_ID_FAVOURITES_FOOTER",
    "AD_UNIT_ID_HELP_FOOTER"
)

fun com.android.build.api.dsl.ApplicationBuildType.adMobIds(appId: String, unitId: (String) -> String) {
    manifestPlaceholders["ADMOB_APP_ID"] = appId
    buildConfigField("String", "ADMOB_APP_ID", javaString(appId))
    adUnitKeys.forEach { buildConfigField("String", it, javaString(unitId(it))) }
}

// Why a release id is unusable, or null when it is a real one.
fun releaseAdIdProblem(name: String, value: String, separator: Char): String? {
    val format = Regex("ca-app-pub-(\\d{16})\\$separator\\d{10}")
    val publisher = format.matchEntire(value)?.groupValues?.get(1)
    return when {
        value.isBlank() -> "$name is missing from android/secrets.properties"
        value.startsWith(adMobTestPublisher) -> "$name is one of Google's test ids"
        publisher == null -> "$name is not an AdMob id (ca-app-pub-<16 digits>$separator<10 digits>)"
        publisher.all { it == '0' } -> "$name is the placeholder from secrets.example.properties"
        else -> null
    }
}
val releaseAdIdProblems = buildList {
    releaseAdIdProblem("ADMOB_APP_ID", secret("ADMOB_APP_ID"), '~')?.let(::add)
    adUnitKeys.forEach { key -> releaseAdIdProblem(key, secret(key), '/')?.let(::add) }
    // Ad units belong to the app id's AdMob account: a different publisher means an id was
    // copied from another account.
    if (isEmpty()) {
        val publisher = secret("ADMOB_APP_ID").substringBefore('~')
        adUnitKeys.filter { secret(it).substringBefore('/') != publisher }
            .forEach { add("$it is from a different AdMob account than ADMOB_APP_ID") }
    }
}
val verifyReleaseAdIds by tasks.registering {
    description = "Fails when a release build would ship AdMob test, placeholder or malformed ids."
    val problems = releaseAdIdProblems
    doLast {
        if (problems.isNotEmpty()) {
            throw GradleException(
                "Release builds need the real AdMob ids in android/secrets.properties:\n  " +
                    problems.joinToString("\n  ")
            )
        }
    }
}
// Packaging a release APK or bundle (and so every Play upload) runs the check first. Release
// unit tests and lint don't package, so CI's example config still builds them.
tasks.matching { it.name == "packageRelease" || it.name == "packageReleaseBundle" }.configureEach {
    dependsOn(verifyReleaseAdIds)
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
        versionCode = 3_000_002
        versionName = "2.0.2"

        buildConfigField("String", "API_DOMAIN", javaString(secret("API_DOMAIN")))
        buildConfigField("String", "DIRECTUS_URL", javaString(secret("DIRECTUS_URL")))
        buildConfigField("String", "DIRECTUS_FEEDBACK_TOKEN", javaString(secret("DIRECTUS_FEEDBACK_TOKEN")))
        buildConfigField("String", "DIRECTUS_COOPERATE_TOKEN", javaString(secret("DIRECTUS_COOPERATE_TOKEN")))
        // The webcam host (FOX-92): station cams, their hourly history and the manifest.
        buildConfigField("String", "STATION_CAMS_URL", javaString(secret("STATION_CAMS_URL")))
        manifestPlaceholders["MAPS_API_KEY"] = secret("MAPS_API_KEY")
        // AdMob ids are per build type (FOX-61): see buildTypes below.
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
        // Debug builds never report to Analytics or Crashlytics, from the first event on
        // (TrackingManager, FOX-60); release builds report unless the install opted out.
        debug {
            manifestPlaceholders["FIREBASE_COLLECTION_ENABLED"] = "false"
            // Google's test ads only, whatever secrets.properties says (FOX-61).
            adMobIds(adMobTestAppId) { adMobTestBannerUnitId }
        }
        release {
            manifestPlaceholders["FIREBASE_COLLECTION_ENABLED"] = "true"
            // The real ids from secrets.properties; verifyReleaseAdIds checks them.
            adMobIds(secret("ADMOB_APP_ID")) { secret(it) }
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
    // FOX-62: the indices, level bands and colours, Taiwan time and the watch contract, shared with :wear.
    implementation(project(":core"))
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
    // FOX-119: tablets, foldables and flip phones: window size classes and list-detail panes.
    implementation(libs.androidx.compose.material3.adaptive)
    implementation(libs.androidx.compose.material3.adaptive.layout)

    // Home screen widgets (FOX-59): Glance, refreshed by WorkManager (below, with FOX-57).
    implementation(libs.androidx.glance.appwidget)

    // The welcome flow (FOX-96): Lottie, playing the iOS animations from assets/onboarding.
    implementation(libs.lottie.compose)

    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.analytics)
    implementation(libs.firebase.crashlytics)
    // FOX-57: FCM push alerts; the alert sync runs in WorkManager.
    implementation(libs.firebase.messaging)
    implementation(libs.androidx.work.runtime.ktx)

    // The review prompt (FOX-60): Play In-App Review.
    implementation(libs.play.review)

    // FOX-62: favourites, Pro and the language to the Wear OS app; its locked-complication events back.
    implementation(libs.play.services.wearable)

    // On-device translation of Chinese-only API text (FOX-98): ML Kit, the model downloaded on Wi-Fi.
    implementation(libs.mlkit.translate)

    testImplementation(libs.junit)
    testImplementation(libs.okhttp.mockwebserver)
    testImplementation(libs.kotlinx.coroutines.test)
}
