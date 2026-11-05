package com.kfpun.twaqi.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

private val Teal = Color(0xFF00897B)
private val TealLight = Color(0xFF4DB6AC)

private val LightColors = lightColorScheme(
    primary = Teal,
    secondary = Color(0xFF546E7A)
)

private val DarkColors = darkColorScheme(
    primary = TealLight,
    secondary = Color(0xFF90A4AE)
)

/** The app theme: Material 3, with the wallpaper colours on Android 12+ when [dynamicColor] is on. */
@Composable
fun TWAQITheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }

        darkTheme -> DarkColors

        else -> LightColors
    }
    MaterialTheme(colorScheme = colorScheme, content = content)
}
