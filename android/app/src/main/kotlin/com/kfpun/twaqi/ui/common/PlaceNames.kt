package com.kfpun.twaqi.ui.common

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.kfpun.twaqi.data.places.TaiwanPlaceNames

/** The official English names of Taiwan's counties and townships (FOX-114), for `displayLocality`. */
@Composable
fun rememberTaiwanPlaceNames(): TaiwanPlaceNames {
    val context = LocalContext.current
    return remember(context) { TaiwanPlaceNames.get(context) }
}
