package com.kfpun.twaqi.pro

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

/** Prices shown under a plan (iOS: `ProPlanRow.detail`). */
object ProPricing {
    /** The monthly equivalent of a longer plan, so plans compare at a glance. */
    fun perMonth(priceMicros: Long, months: Int, currencyCode: String, locale: Locale = Locale.getDefault()): String {
        val format = NumberFormat.getCurrencyInstance(locale)
        runCatching { format.currency = Currency.getInstance(currencyCode) }
        val digits = format.currency?.defaultFractionDigits?.coerceAtLeast(0) ?: 2
        format.minimumFractionDigits = digits
        format.maximumFractionDigits = digits
        val monthly = BigDecimal.valueOf(priceMicros)
            .divide(BigDecimal.valueOf(1_000_000L * months), digits, RoundingMode.HALF_UP)
        return format.format(monthly)
    }
}
