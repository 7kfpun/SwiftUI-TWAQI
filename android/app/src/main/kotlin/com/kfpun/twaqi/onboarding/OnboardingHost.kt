package com.kfpun.twaqi.onboarding

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.kfpun.twaqi.analytics.Analytics

/**
 * Shows the welcome flow in place of [content] (iOS's full-screen cover): by itself when
 * [opensAtLaunch], and whenever [content] calls its `showWelcomeGuide` (Help). [content] keeps its
 * saved state (the selected tab, Help's page) while the flow is up, and isn't composed under it,
 * so the map's first location request waits until the flow is done, as on iOS.
 */
@Composable
fun OnboardingHost(opensAtLaunch: Boolean, content: @Composable (showWelcomeGuide: () -> Unit) -> Unit) {
    val context = LocalContext.current
    // The run on screen: LAUNCH, "help-<n>", or empty for none. Saved, so rotation keeps the run.
    var run by rememberSaveable { mutableStateOf(if (opensAtLaunch) LAUNCH else "") }
    var helpRuns by rememberSaveable { mutableIntStateOf(0) }
    val home = rememberSaveableStateHolder()

    if (run.isNotEmpty()) {
        val isLaunchFlow = run == LAUNCH
        if (isLaunchFlow) {
            // Shown counts from the moment it opens, so quitting or skipping it doesn't bring it back.
            LaunchedEffect(Unit) {
                if (OnboardingStore(context).markShown()) {
                    Analytics.logEvent(context, Analytics.ONBOARDING_SHOWN, mapOf("label" to "launch"))
                }
            }
        }
        OnboardingScreen(runKey = "onboarding-$run", isLaunchFlow = isLaunchFlow, onFinish = { run = "" })
    } else {
        home.SaveableStateProvider("home") {
            content {
                helpRuns += 1
                run = "help-$helpRuns"
            }
        }
    }
}

private const val LAUNCH = "launch"
