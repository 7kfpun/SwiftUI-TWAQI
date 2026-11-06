package com.kfpun.twaqi.ui.station.share

import android.Manifest
import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.kfpun.twaqi.BuildConfig
import com.kfpun.twaqi.R
import com.kfpun.twaqi.analytics.Analytics
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.data.model.Pollutant
import com.kfpun.twaqi.data.model.Station
import com.kfpun.twaqi.data.model.TaiwanTime
import com.kfpun.twaqi.data.places.TaiwanPlaceNames
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.review.ReviewPrompt
import java.io.File
import java.time.Duration
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * What the card shows (iOS `ShareCardView`'s inputs): one reading, passed in, so the card never
 * depends on the live screen.
 *
 * @property readings PM2.5, PM10 and O3 from the current reading, or null without one; zero means
 *   the station doesn't measure it.
 */
data class ShareCardContent(
    val title: String,
    val locality: String?,
    val aqi: Double,
    val readings: List<Pair<AirIndexType, Double>>?,
    val publishTime: String?
) {
    companion object {
        /** Shown under the AQI; the rest of the grid is too much for a card. */
        val pollutants: List<AirIndexType> = listOf(AirIndexType.PM25, AirIndexType.PM10, AirIndexType.O3)

        fun readings(pollutant: Pollutant?): List<Pair<AirIndexType, Double>>? =
            pollutant?.let { reading -> pollutants.map { it to reading.value(it) } }

        /**
         * The line under the title, as the station page shows it: the township, then the county,
         * with English names from [places] (FOX-114).
         */
        fun locality(
            pollutant: Pollutant?,
            station: Station?,
            chinese: Boolean,
            places: TaiwanPlaceNames = TaiwanPlaceNames.EMPTY
        ): String? = pollutant?.displayLocality(chinese, places) ?: station?.displayLocality(chinese, places)
    }
}

/** What the reader did with the card, for `share_card`'s `action` (iOS `ShareCardAction`). */
enum class ShareCardAction(val raw: String) {
    /** Opened the system share sheet with the card. */
    SHARE("share"),

    /** Saved the card to Photos. */
    SAVE("save"),

    /** Closed the preview without sharing or saving. */
    CANCEL("cancel")
}

/** iOS `ShareCardSharing.SaveResult`. */
enum class ShareCardSaveResult {
    SAVED,

    /** Android 8–9 only: the reader said no to the storage permission; only Settings can undo it. */
    DENIED,
    FAILED
}

/**
 * Turns the card into a PNG and hands it to the Android share sheet or Photos (iOS
 * `ShareCardSharing`). The preview ([ShareCardPreview]) comes first.
 */
object ShareCardSharing {
    /** Below Android 10 (API 29) MediaStore needs `WRITE_EXTERNAL_STORAGE` to add a photo. */
    const val SCOPED_STORAGE_SDK = Build.VERSION_CODES.Q

    /** Inside `cacheDir`, which needs no permission and which Android may clear at any time. */
    const val CACHE_DIRECTORY = "share-cards"

    /** Where saved cards go, under Pictures. */
    const val ALBUM = "Taiwan Air"

    /** Cards left in [CACHE_DIRECTORY] by earlier shares are removed after this long. */
    val cacheMaxAge: Duration = Duration.ofDays(1)

    private val fileTime: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")

    /** Whether saving to Photos on [sdkInt] needs the storage permission asked for at runtime. */
    fun needsWritePermission(sdkInt: Int): Boolean = sdkInt < SCOPED_STORAGE_SDK

    /**
     * `TaiwanAir-12-4x5-20260807-220512.png`: the station, the shape and when it was made, in
     * Taiwan time, so two cards never share a name in the share cache or in Photos.
     */
    fun fileName(stationId: Int, shape: ShareCardShape, now: Instant = Instant.now()): String =
        "TaiwanAir-$stationId-${shape.raw}-${fileTime.format(now.atZone(TaiwanTime.zone))}.png"

    /** The line sent with the card: "Keelung: AQI 54, Moderate — via Taiwan Air". */
    fun message(format: String, title: String, aqi: Double, statusLabel: String): String =
        String.format(Locale.US, format, title, aqi.toInt(), statusLabel)

    fun message(context: Context, title: String, aqi: Double): String {
        val localized = AppLocale.localizedContext(context)
        val status = AirStatus.of(AirIndexType.AQI, aqi)
        return message(
            localized.getString(R.string.share_message),
            title,
            aqi,
            localized.getString(status.label)
        )
    }

    /** The message and the Play listing, as the share sheet's text (iOS: the App Store link). */
    fun shareText(message: String, storeUrl: String = ReviewPrompt.storeListingUrl): String = "$message\n$storeUrl"

    /** The analytics parameters (iOS `parameters(card:stationId:action:)`); `action` only on `share_card`. */
    fun parameters(
        aqi: Double,
        shape: ShareCardShape,
        stationId: Int,
        action: ShareCardAction? = null
    ): Map<String, Any> = buildMap {
        put("stationId", stationId)
        put("aqi", aqi.toInt())
        put("shape", shape.raw)
        action?.let { put("action", it.raw) }
    }

    /** The preview opened: the top of the share funnel. */
    fun logPreviewOpened(context: Context, aqi: Double, shape: ShareCardShape, stationId: Int) =
        Analytics.logEvent(context, Analytics.SHARE_CARD_PREVIEW_OPENED, parameters(aqi, shape, stationId))

    fun log(context: Context, action: ShareCardAction, aqi: Double, shape: ShareCardShape, stationId: Int) =
        Analytics.logEvent(context, Analytics.SHARE_CARD, parameters(aqi, shape, stationId, action))

    /**
     * Writes [bitmap] to the share cache and returns its `content://` URI from the app's
     * FileProvider. Call off the main thread. Older cards are pruned first.
     */
    fun writeToCache(context: Context, bitmap: Bitmap, name: String): Uri {
        val directory = File(context.cacheDir, CACHE_DIRECTORY).apply { mkdirs() }
        prune(directory)
        val file = File(directory, name)
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        return FileProvider.getUriForFile(context, fileProviderAuthority, file)
    }

    /** Deletes cards in [directory] last written more than [cacheMaxAge] before [now]. */
    fun prune(directory: File, now: Instant = Instant.now()): List<File> = directory.listFiles().orEmpty()
        .filter { it.isFile && Duration.between(Instant.ofEpochMilli(it.lastModified()), now) > cacheMaxAge }
        .filter { it.delete() }

    /** The Android share sheet with the card, the message as its title and the text to send. */
    fun shareIntent(uri: Uri, message: String, text: String): Intent {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TEXT, text)
            putExtra(Intent.EXTRA_TITLE, message)
            // The sheet's preview of the card, and read access for whoever receives it.
            clipData = ClipData.newRawUri(message, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return Intent.createChooser(send, null)
    }

    fun hasWritePermission(context: Context): Boolean = !needsWritePermission(Build.VERSION.SDK_INT) ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
        PackageManager.PERMISSION_GRANTED

    /**
     * Adds [bitmap] to Photos (Pictures/Taiwan Air) through MediaStore. Android 10+ needs no
     * permission; below that the caller asks for `WRITE_EXTERNAL_STORAGE` first. Call off the main
     * thread.
     */
    fun saveToPhotos(context: Context, bitmap: Bitmap, name: String): ShareCardSaveResult {
        if (!hasWritePermission(context)) return ShareCardSaveResult.DENIED
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveScoped(context, bitmap, name)
            } else {
                saveLegacy(context, bitmap, name)
            }
            ShareCardSaveResult.SAVED
        } catch (_: Exception) {
            ShareCardSaveResult.FAILED
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveScoped(context: Context, bitmap: Bitmap, name: String) {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/$ALBUM")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values) ?: error("MediaStore refused the insert")
        try {
            val written = resolver.openOutputStream(uri)?.use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            check(written == true) { "The card couldn't be written" }
            resolver.update(uri, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    /** Android 8–9: a file in Pictures, then added to MediaStore so Photos shows it at once. */
    @Suppress("DEPRECATION")
    private fun saveLegacy(context: Context, bitmap: Bitmap, name: String) {
        val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), ALBUM)
        check(directory.isDirectory || directory.mkdirs()) { "No Pictures folder" }
        val file = File(directory, name)
        val written = file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        check(written) { "The card couldn't be written" }
        MediaScannerConnection.scanFile(context, arrayOf(file.absolutePath), arrayOf("image/png"), null)
    }

    private val fileProviderAuthority: String get() = "${BuildConfig.APPLICATION_ID}.fileprovider"
}

/**
 * One opening of the share preview, for its `cancel` event (iOS `ShareCardSession`): the preview
 * closed with no share and no successful save.
 *
 * A share or a successful save commits the session for good; a failed or denied save never undoes
 * that. A save still running when the preview goes leaves the call to that save: it logs `cancel`
 * only if it fails.
 */
class ShareCardSession(isCommitted: Boolean = false, didCancel: Boolean = false) {
    var isCommitted: Boolean = isCommitted
        private set
    private var savesInFlight = 0
    private var isGone = false
    var didCancel: Boolean = didCancel
        private set

    fun appeared() {
        isGone = false
    }

    fun shared() {
        isCommitted = true
    }

    fun saveStarted() {
        savesInFlight += 1
    }

    /** Whether to log `cancel` now. */
    fun saveFinished(saved: Boolean): Boolean {
        savesInFlight = maxOf(0, savesInFlight - 1)
        if (saved) isCommitted = true
        return cancelIfDue()
    }

    /** Whether to log `cancel` now. */
    fun disappeared(): Boolean {
        isGone = true
        return cancelIfDue()
    }

    private fun cancelIfDue(): Boolean {
        if (!isGone || isCommitted || savesInFlight != 0 || didCancel) return false
        didCancel = true
        return true
    }
}
