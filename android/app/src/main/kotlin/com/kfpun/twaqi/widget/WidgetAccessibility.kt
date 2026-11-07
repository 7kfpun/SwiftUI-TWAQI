package com.kfpun.twaqi.widget

import androidx.annotation.StringRes
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirIndexType

/** A string resource and its arguments, resolved in the widget's language by [WidgetText.string]. */
data class WidgetString(@StringRes val id: Int, val args: List<Any>) {
    fun resolve(text: WidgetText): String = text.string(id, *args.toTypedArray())
}

/** What TalkBack reads for the widget's controls (FOX-120, iOS `accessibilityLabel`s in `TWAQIWidget.swift`). */
object WidgetAccessibility {
    /** The tappable index label: "Show PM2.5", the index a tap steps to (iOS `Widget.show_index`). */
    fun showIndex(shown: AirIndexType): WidgetString =
        WidgetString(R.string.widget_show_index, listOf(WidgetPaging.nextIndex(shown).label))

    /** The pager's "2 / 5": "Station 2 of 5", counting from 1 (iOS `Widget.page_position`). */
    fun pagePosition(page: Int, count: Int): WidgetString =
        WidgetString(R.string.widget_page_position, listOf(page + 1, count))
}
