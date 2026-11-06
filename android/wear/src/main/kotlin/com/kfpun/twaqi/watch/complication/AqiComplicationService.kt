package com.kfpun.twaqi.watch.complication

import android.app.PendingIntent
import android.content.Context
import android.graphics.drawable.Icon
import androidx.wear.watchface.complications.data.ColorRamp
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationText
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.data.SmallImage
import androidx.wear.watchface.complications.data.SmallImageComplicationData
import androidx.wear.watchface.complications.data.SmallImageType
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirLevel
import com.kfpun.twaqi.watch.R
import com.kfpun.twaqi.watch.data.WatchLocale
import com.kfpun.twaqi.watch.data.WatchPro
import com.kfpun.twaqi.watch.data.WatchReading
import com.kfpun.twaqi.watch.data.WatchRepository
import com.kfpun.twaqi.watch.data.WatchStore
import com.kfpun.twaqi.watch.relay.PhoneRelay
import com.kfpun.twaqi.watch.ui.WatchActivity
import com.kfpun.twaqi.wearable.LockedComplicationHit

/**
 * The watch-face complication (iOS `TWAQIWatchWidget`): the index the reader picked, in the style
 * they picked (`ComplicationConfigActivity`), for the station the app follows. The face style is
 * free without its number; every other style needs Pro and shows a lock without it (FOX-63).
 * Updated every 30 minutes (the manifest) and whenever the app fetches a reading or Pro changes.
 */
class AqiComplicationService : SuspendingComplicationDataSourceService() {
    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        val family = family(request.complicationType) ?: return null
        val store = WatchStore.get(this)
        val (index, style) = config(store, request.complicationInstanceId)
        val access = ComplicationAccess.of(style, WatchPro.isUnlocked(store))

        if (access == ComplicationAccess.LOCKED) {
            // The locked-style event (FOX-63, FOX-44): queued once per setup, logged by the phone.
            LockedComplicationLog(store).record(
                LockedComplicationHit(style = style.id, family = request.complicationType.name, index = index.key)
            )
            PhoneRelay.flush(this)
            return data(request.complicationType, family, null, index, style, access)
        }

        // Falls back to the cached reading offline rather than blanking the complication.
        val reading = WatchRepository.get(this).followedReading()
        return data(request.complicationType, family, reading, index, style, access)
    }

    override fun onComplicationDeactivated(complicationInstanceId: Int) {
        WatchStore.get(this).removeComplicationConfig(complicationInstanceId)
    }

    /** The face picker's preview: the placeholder station, every style as designed. */
    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        val family = family(type) ?: return null
        return data(
            type,
            family,
            WatchReading.placeholder,
            AirIndexType.AQI,
            ComplicationStyle.DEFAULT,
            ComplicationAccess.FULL
        )
    }

    private fun data(
        type: ComplicationType,
        family: ComplicationFamily,
        reading: WatchReading?,
        index: AirIndexType,
        style: ComplicationStyle,
        access: ComplicationAccess
    ): ComplicationData {
        val localized = WatchLocale.wrap(this)
        val content = ComplicationContent.build(
            family,
            reading,
            index,
            style,
            access,
            words(localized),
            WatchLocale.isChinese(localized)
        )
        val description = text(content.description)
        val tap = tapIntent(this, content.locked)
        val face = content.face?.let(::faceImage)
        val icon = content.icon?.let(::monochrome)
        return when (type) {
            ComplicationType.RANGED_VALUE -> RangedValueComplicationData.Builder(
                value = content.progress ?: 0f,
                min = 0f,
                max = 1f,
                contentDescription = description
            ).apply {
                if (content.text.isNotEmpty()) setText(text(content.text))
                content.title?.let { setTitle(text(it)) }
                face?.let(::setSmallImage)
                icon?.let(::setMonochromaticImage)
                if (content.level != null) setColorRamp(LEVEL_RAMP)
            }.setTapAction(tap).build()

            ComplicationType.LONG_TEXT -> LongTextComplicationData.Builder(text(content.text), description).apply {
                content.title?.let { setTitle(text(it)) }
                face?.let(::setSmallImage)
                icon?.let(::setMonochromaticImage)
            }.setTapAction(tap).build()

            ComplicationType.SMALL_IMAGE -> SmallImageComplicationData.Builder(
                face
                    ?: SmallImage.Builder(
                        Icon.createWithResource(this, R.drawable.ic_lock),
                        SmallImageType.ICON
                    ).build(),
                description
            ).setTapAction(tap).build()

            else -> ShortTextComplicationData.Builder(text(content.text), description).apply {
                content.title?.let { setTitle(text(it)) }
                face?.let(::setSmallImage)
                icon?.let(::setMonochromaticImage)
            }.setTapAction(tap).build()
        }
    }

    private fun faceImage(level: AirLevel): SmallImage? {
        val drawable = faceDrawable(level) ?: return null
        return SmallImage.Builder(Icon.createWithResource(this, drawable), SmallImageType.PHOTO).build()
    }

    private fun monochrome(icon: ComplicationIcon): MonochromaticImage = MonochromaticImage.Builder(
        Icon.createWithResource(
            this,
            when (icon) {
                ComplicationIcon.LOCK -> R.drawable.ic_lock
                ComplicationIcon.AIR -> R.drawable.ic_air
            }
        )
    ).build()

    companion object {
        /** The six level colours along the ring, not blended (iOS: the ring in the band's colour). */
        private val LEVEL_RAMP = ColorRamp(
            AirLevel.showAllCases.map { 0xFF000000.toInt() or it.color }.toIntArray(),
            interpolated = false
        )

        fun family(type: ComplicationType): ComplicationFamily? = when (type) {
            ComplicationType.RANGED_VALUE -> ComplicationFamily.RANGED
            ComplicationType.SHORT_TEXT -> ComplicationFamily.SHORT
            ComplicationType.LONG_TEXT -> ComplicationFamily.LONG
            ComplicationType.SMALL_IMAGE -> ComplicationFamily.IMAGE
            else -> null
        }

        fun config(store: WatchStore, id: Int): Pair<AirIndexType, ComplicationStyle> {
            val (index, style) = store.complicationConfig(id)
            return (AirIndexType.fromKey(index) ?: AirIndexType.AQI) to ComplicationStyle.fromId(style)
        }

        fun words(context: Context): ComplicationWords = object : ComplicationWords {
            override fun status(level: AirLevel): String = context.getString(statusLabel(level))

            override val proLocked: String = context.getString(R.string.watch_pro_locked)

            override val noStation: String = context.getString(R.string.watch_no_station)
        }

        /** Opens the app; a lock opens its paywall. */
        fun tapIntent(context: Context, locked: Boolean): PendingIntent = PendingIntent.getActivity(
            context,
            if (locked) 1 else 0,
            WatchActivity.intent(context, openPaywall = locked),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        private fun text(value: String): ComplicationText = PlainComplicationText.Builder(value).build()
    }
}

/** The phone app's face for [level]; none for an unknown level. */
fun faceDrawable(level: AirLevel): Int? = when (level) {
    AirLevel.GOOD -> R.drawable.status_good
    AirLevel.MODERATE -> R.drawable.status_moderate
    AirLevel.UNHEALTHY_FOR_SENSITIVE_GROUP -> R.drawable.status_unhealthyforsensitivegroup
    AirLevel.UNHEALTHY -> R.drawable.status_unhealthy
    AirLevel.VERY_UNHEALTHY -> R.drawable.status_veryunhealthy
    AirLevel.HAZARDOUS -> R.drawable.status_hazardous
    AirLevel.UNKNOWN -> null
}

/** The level's name, as the phone shows it. */
fun statusLabel(level: AirLevel): Int = when (level) {
    AirLevel.GOOD -> R.string.airstatus_good
    AirLevel.MODERATE -> R.string.airstatus_moderate
    AirLevel.UNHEALTHY_FOR_SENSITIVE_GROUP -> R.string.airstatus_unhealthyforsensitivegroup
    AirLevel.UNHEALTHY -> R.string.airstatus_unhealthy
    AirLevel.VERY_UNHEALTHY -> R.string.airstatus_veryunhealthy
    AirLevel.HAZARDOUS -> R.string.airstatus_hazardous
    AirLevel.UNKNOWN -> R.string.airstatus_unknown
}
