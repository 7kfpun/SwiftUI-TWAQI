package com.kfpun.twaqi.watch.complication

/**
 * How a complication shows its index (iOS `ComplicationStyle`, FOX-63). [id] is what is saved per
 * complication; never rename one, or complications already on a face reset.
 */
enum class ComplicationStyle(val id: String) {
    /** "AQI 42": the index name, the number and, with room, the unit. */
    LABELLED("labelled"),

    /** "42": just the number. */
    NUMBER_ONLY("numberOnly"),

    /** The phone app's face for the band, with the number where it fits. Free without Pro, minus the number. */
    FACE("face"),

    /** "Moderate": the health level in words, no number at all. */
    STATUS("status");

    /** Every style but the face needs Pro; so does the face's number. */
    val isPro: Boolean get() = this != FACE

    companion object {
        /** iOS `SelectIndexIntent.style` defaults to labelled. */
        val DEFAULT = LABELLED

        fun fromId(id: String?): ComplicationStyle = entries.firstOrNull { it.id == id } ?: DEFAULT
    }
}

/** What a complication may draw for the reader (iOS `ComplicationAccess`, FOX-63). */
enum class ComplicationAccess {
    /** Pro: the style as designed, number included. */
    FULL,

    /** The free face: the band's face in its colour, never the number. */
    FACE_ONLY,

    /** A Pro style without Pro: a lock that reads "Pro", no reading. */
    LOCKED;

    /** Whether the number (or the unit next to it) may be drawn. */
    val showsNumber: Boolean get() = this == FULL

    companion object {
        fun of(style: ComplicationStyle, isPro: Boolean): ComplicationAccess = when {
            isPro -> FULL
            style.isPro -> LOCKED
            else -> FACE_ONLY
        }
    }
}
