package com.kfpun.twaqi.shortcuts

import com.kfpun.twaqi.data.model.AirStatus
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element

/**
 * The answer's sentences as `values/strings.xml` (en) and `values-zh-rTW/strings.xml` (zh-Hant)
 * hold them, read from the files, so the tests check the shipped wording without Android.
 * Unit tests run from the module directory (android/app).
 */
object ResourceStrings {
    val english: AnswerStrings by lazy { answerStrings("values", chinese = false) }
    val chinese: AnswerStrings by lazy { answerStrings("values-zh-rTW", chinese = true) }

    private fun answerStrings(folder: String, chinese: Boolean): AnswerStrings {
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder()
            .parse(File("src/main/res/$folder/strings.xml"))
        val strings = document.getElementsByTagName("string").let { nodes ->
            (0 until nodes.length).associate {
                val element = nodes.item(it) as Element
                element.getAttribute("name") to unescape(element.textContent)
            }
        }
        val plurals = document.getElementsByTagName("plurals").let { nodes ->
            (0 until nodes.length).associate { index ->
                val element = nodes.item(index) as Element
                val items = element.getElementsByTagName("item")
                element.getAttribute("name") to (0 until items.length).associate {
                    val item = items.item(it) as Element
                    item.getAttribute("quantity") to unescape(item.textContent)
                }
            }
        }
        fun string(name: String) = checkNotNull(strings[name]) { "$folder/strings.xml has no $name" }
        return AnswerStrings(
            chinese = chinese,
            fallbackFavourite = string("intent_answer_fallback_favourite"),
            fallbackDefault = string("intent_answer_fallback_default"),
            noReading = string("intent_answer_no_reading"),
            noAqi = string("intent_answer_no_aqi"),
            reading = string("intent_answer_reading"),
            mainPollutant = string("intent_answer_main_pollutant"),
            guidance = string("intent_answer_guidance"),
            cachedAge = string("intent_answer_cached_age"),
            cached = string("intent_answer_cached"),
            oldAge = string("intent_answer_old_age"),
            status = { string("airstatus_${it.key}") },
            publicGuidance = { status: AirStatus -> string("airstatus_general_public_guidance_${status.key}") },
            age = { unit, count ->
                val name = when (unit) {
                    AgeUnit.MINUTES -> "intent_age_minutes"
                    AgeUnit.HOURS -> "intent_age_hours"
                    AgeUnit.DAYS -> "intent_age_days"
                }
                val items = checkNotNull(plurals[name]) { "$folder/strings.xml has no plurals $name" }
                val template = (if (count == 1) items["one"] else null) ?: items.getValue("other")
                template.replace("%d", count.toString())
            }
        )
    }

    private fun unescape(text: String) = text.replace("\\'", "'").replace("\\\"", "\"")
}
