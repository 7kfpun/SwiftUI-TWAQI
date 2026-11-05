package com.kfpun.twaqi.ui.help

/**
 * The Help tab's sections, top to bottom (iOS `HelpSection`).
 *
 * The iOS sections still to come on Android slot in where iOS has them: the welcome guide
 * after [APPEARANCE] (FOX-96), and the developer
 * section last (FOX-60). The feedback row joins [CONTACT] with FOX-60.
 */
enum class HelpSection {
    PURCHASE,

    /** Quiet hours for alerts, and "cancel all" (FOX-57). */
    DO_NOT_DISTURB,
    LANGUAGE,
    APPEARANCE,
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

    data object Cooperate : HelpDestination {
        override val route = "cooperate"
    }

    companion object {
        fun fromRoute(route: String): HelpDestination? = when {
            route.startsWith("guide/") -> DefinitionPage.fromKey(route.removePrefix("guide/"))?.let(::IndexGuide)
            route == WidgetGuide.route -> WidgetGuide
            route == WearOsGuide.route -> WearOsGuide
            route == Cooperate.route -> Cooperate
            else -> null
        }
    }
}
