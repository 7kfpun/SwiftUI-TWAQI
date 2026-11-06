package com.kfpun.twaqi.watch.complication

import com.kfpun.twaqi.data.model.AirIndexType
import com.kfpun.twaqi.data.model.AirLevel
import com.kfpun.twaqi.watch.data.WatchReading

/** The complication slots TWAQI fills, the Wear OS side of iOS's WidgetKit families. */
enum class ComplicationFamily {
    /** A ring with text (iOS `accessoryCircular`). */
    RANGED,

    /** A short line, with an icon or a title (iOS `accessoryCorner` / `accessoryInline`). */
    SHORT,

    /** Two lines (iOS `accessoryRectangular`). */
    LONG,

    /** Just an image: the face. */
    IMAGE
}

/** A monochrome glyph the watch face tints. */
enum class ComplicationIcon { LOCK, AIR }

/** The words a complication needs, in the watch's language. */
interface ComplicationWords {
    fun status(level: AirLevel): String

    /** "Pro · Open the app to unlock". */
    val proLocked: String

    /** "Open the app to choose a station". */
    val noStation: String
}

/**
 * What one complication draws (iOS `ReadingWidgetView`), worked out without any Wear OS types so
 * it can be tested. `AqiComplicationService` turns it into `ComplicationData`.
 *
 * @property progress 0–1: how far up the six levels the reading sits (a band, not the raw value,
 *   so AQI and CO in ppm read on the same scale).
 * @property face the level whose face to show, in its colours.
 */
data class ComplicationContent(
    val text: String,
    val title: String? = null,
    val description: String,
    val progress: Float? = null,
    val face: AirLevel? = null,
    val icon: ComplicationIcon? = null,
    val level: AirLevel? = null,
    val locked: Boolean = false
) {
    companion object {
        const val PRO = "Pro"
        private const val NO_VALUE = "--"

        fun build(
            family: ComplicationFamily,
            reading: WatchReading?,
            type: AirIndexType,
            style: ComplicationStyle,
            access: ComplicationAccess,
            words: ComplicationWords,
            chinese: Boolean
        ): ComplicationContent {
            if (access == ComplicationAccess.LOCKED) return locked(family, type, words)
            if (reading == null) return empty(family, type, style, words)

            val level = reading.level(type)
            val status = words.status(level)
            val value = reading.formatted(type)
            val station = reading.displayName(chinese)
            val showsNumber = access.showsNumber
            val description = "${type.label} $value · $status · $station"
            val progress = bandProgress(level)
            val face = level.takeIf { it.hasFaceImage }

            return when (family) {
                ComplicationFamily.RANGED -> when (style) {
                    // The face fills the slot; the ring still tracks the band. Never the number on the ring.
                    ComplicationStyle.FACE -> ComplicationContent(
                        text = "",
                        description = if (showsNumber) description else "${type.label} · $status · $station",
                        progress = progress,
                        face = face ?: level,
                        level = level
                    )

                    ComplicationStyle.STATUS -> ComplicationContent(
                        text = status,
                        description = "${type.label} · $status · $station",
                        progress = progress,
                        level = level
                    )

                    else -> ComplicationContent(
                        text = value,
                        title = type.label.takeIf { style == ComplicationStyle.LABELLED },
                        description = description,
                        progress = progress,
                        level = level
                    )
                }

                ComplicationFamily.SHORT -> when (style) {
                    // Without Pro the line names the index instead of the number, so a PM2.5 face isn't read as the AQI.
                    ComplicationStyle.FACE -> ComplicationContent(
                        text = if (showsNumber) value else type.label,
                        description = if (showsNumber) description else "${type.label} · $status · $station",
                        face = face ?: level,
                        level = level
                    )

                    ComplicationStyle.STATUS -> ComplicationContent(
                        text = status,
                        title = type.label,
                        description = "${type.label} · $status · $station",
                        icon = ComplicationIcon.AIR,
                        level = level
                    )

                    ComplicationStyle.NUMBER_ONLY -> ComplicationContent(
                        text = value,
                        description = description,
                        level = level
                    )

                    ComplicationStyle.LABELLED -> ComplicationContent(
                        text = value,
                        title = type.label,
                        description = description,
                        level = level
                    )
                }

                ComplicationFamily.LONG -> when (style) {
                    // The status style names the index, so a PM2.5 level isn't read as the AQI.
                    ComplicationStyle.STATUS -> ComplicationContent(
                        text = status,
                        title = "${type.label} · $station",
                        description = "${type.label} · $status · $station",
                        face = face,
                        level = level
                    )

                    else -> ComplicationContent(
                        text = "$status · ${numberLine(type, style, value, showsNumber)}",
                        title = station,
                        description = if (showsNumber) description else "${type.label} · $status · $station",
                        face = face,
                        level = level
                    )
                }

                ComplicationFamily.IMAGE -> ComplicationContent(
                    text = "",
                    description = if (showsNumber) description else "${type.label} · $status · $station",
                    face = face ?: level,
                    level = level
                )
            }
        }

        /** How far up the six levels [level] sits, 0 to 1 (iOS `bandProgress`). */
        fun bandProgress(level: AirLevel): Float {
            val band = AirLevel.showAllCases.indexOf(level) + 1
            return band.toFloat() / AirLevel.showAllCases.size
        }

        /** The long slot's number part. The free face names the index only; the face beside it shows the level. */
        private fun numberLine(
            type: AirIndexType,
            style: ComplicationStyle,
            value: String,
            showsNumber: Boolean
        ): String = when {
            !showsNumber -> type.label
            style == ComplicationStyle.NUMBER_ONLY -> value
            type.unit.isEmpty() -> "${type.label} $value"
            else -> "${type.label} $value ${type.unit}"
        }

        /** A Pro style without Pro: reads "Pro" and points the reader at the app, where the paywall is. */
        private fun locked(family: ComplicationFamily, type: AirIndexType, words: ComplicationWords) = when (family) {
            ComplicationFamily.LONG -> ComplicationContent(
                text = words.proLocked,
                title = "${type.label} · $PRO",
                description = "${type.label} · ${words.proLocked}",
                icon = ComplicationIcon.LOCK,
                locked = true
            )

            else -> ComplicationContent(
                text = PRO,
                description = "${type.label} · ${words.proLocked}",
                icon = ComplicationIcon.LOCK,
                locked = true
            )
        }

        /** No station yet: the app's first launch sets one. */
        private fun empty(
            family: ComplicationFamily,
            type: AirIndexType,
            style: ComplicationStyle,
            words: ComplicationWords
        ) = when (family) {
            ComplicationFamily.LONG -> ComplicationContent(text = words.noStation, description = words.noStation)

            else -> ComplicationContent(
                text = if (style == ComplicationStyle.LABELLED) "${type.label} $NO_VALUE" else NO_VALUE,
                description = words.noStation,
                progress = if (family == ComplicationFamily.RANGED) 0f else null
            )
        }
    }
}
