package com.kfpun.twaqi.ui.help

/**
 * The Help tab's sections, top to bottom (iOS `HelpSection`).
 *
 * iOS's developer section has no Android counterpart: tapping the version row 7 times toggles the
 * analytics opt-out directly (FOX-60).
 */
enum class HelpSection {
    PURCHASE,

    /** Quiet hours for alerts, and "cancel all" (FOX-57). */
    DO_NOT_DISTURB,
    LANGUAGE,
    APPEARANCE,

    /** "Show welcome guide": runs the welcome flow again (FOX-96). */
    WELCOME,
    CONTACT,
    WIDGETS_AND_WATCH,
    DEFINITION,
    ABOUT
    ;

    companion object {
        /** Premium leads the list so free users see it first (iOS FOX-68); Pro users don't get it. */
        fun order(isPro: Boolean): List<HelpSection> = entries.filter { it != PURCHASE || !isPro }
    }
}

/** The pages Help opens; [route] is what the back stack saves. */
sealed interface HelpDestination {
    val route: String

    data class IndexGuide(val page: DefinitionPage) : HelpDestination {
        override val route: String get() = "guide/${page.key}"
    }

    data object WidgetGuide : HelpDestination {
        override val route = "widgets"
    }

    data object WearOsGuide : HelpDestination {
        override val route = "wear"
    }

    data object ShortcutsGuide : HelpDestination {
        override val route = "shortcuts"
    }

    data object Cooperate : HelpDestination {
        override val route = "cooperate"
    }

    data object Feedback : HelpDestination {
        override val route = "feedback"
    }

    companion object {
        fun fromRoute(route: String): HelpDestination? = when {
            route.startsWith("guide/") -> DefinitionPage.fromKey(route.removePrefix("guide/"))?.let(::IndexGuide)
            route == WidgetGuide.route -> WidgetGuide
            route == WearOsGuide.route -> WearOsGuide
            route == ShortcutsGuide.route -> ShortcutsGuide
            route == Cooperate.route -> Cooperate
            route == Feedback.route -> Feedback
            else -> null
        }
    }
}
