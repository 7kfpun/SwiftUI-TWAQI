package com.kfpun.twaqi.ui.station.share

import android.Manifest
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.edit
import com.kfpun.twaqi.R
import com.kfpun.twaqi.data.model.AirStatus
import com.kfpun.twaqi.locale.AppLocale
import com.kfpun.twaqi.ui.common.rememberTaiwanPlaceNames
import com.kfpun.twaqi.ui.common.rgb
import com.kfpun.twaqi.ui.common.secondaryText
import com.kfpun.twaqi.ui.station.StationDetailsUiState
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The station page's share button (iOS `DetailsView.shareButton`), in the top bar before the heart.
 * Disabled until there is a reading: a card saying "—" is not worth sending anyone. Opens the
 * preview first (FOX-94, iOS FOX-73).
 */
@Composable
fun ShareCardButton(state: StationDetailsUiState) {
    val context = LocalContext.current
    var showing by rememberSaveable { mutableStateOf(false) }
    val aqi = state.currentAqi(Instant.now())
    // The township comes in Chinese only; named as on the station page (FOX-114).
    val places = rememberTaiwanPlaceNames()
    IconButton(onClick = { showing = true }, enabled = aqi > 0) {
        Icon(painterResource(R.drawable.ic_share), contentDescription = stringResource(R.string.share_share))
    }
    if (showing) {
        val chinese = AppLocale.isChinese(context)
        val pollutant = state.pollutant
        val station = state.station
        val content = ShareCardContent(
            title = pollutant?.displayName(chinese) ?: station?.displayName(chinese) ?: "",
            locality = ShareCardContent.locality(pollutant, station, chinese, places),
            aqi = aqi,
            readings = ShareCardContent.readings(pollutant),
            publishTime = state.latestPublishTime
        )
        ShareCardPreview(content, state.stationId, onDismiss = { showing = false })
    }
}

/**
 * The card as it will be sent, a shape for where it's going, then Share or Save to Photos (iOS
 * `ShareCardPreviewView`). The preview is the rendered image itself, so what is shared or saved is
 * exactly what the reader saw.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ShareCardPreview(content: ShareCardContent, stationId: Int, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences(SETTINGS_PREFS, Context.MODE_PRIVATE) }
    var shape by rememberSaveable {
        mutableStateOf(ShareCardShape.fromRaw(prefs.getString(ShareCardShape.PREFERENCE_KEY, null)))
    }
    var image by remember { mutableStateOf<ImageBitmap?>(null) }
    var saveResult by rememberSaveable { mutableStateOf<ShareCardSaveResult?>(null) }
    var isSaving by remember { mutableStateOf(false) }
    // Decides when closing counts as a cancel; kept across a rotation, which is not a close.
    val session = rememberSaveable(saver = sessionSaver) { ShareCardSession() }
    var didLogOpen by rememberSaveable { mutableStateOf(false) }

    DisposableEffect(Unit) {
        session.appeared()
        if (!didLogOpen) {
            didLogOpen = true
            ShareCardSharing.logPreviewOpened(context, content.aqi, shape, stationId)
        }
        // Cancel, back, or the station page going away; not a rotation.
        onDispose {
            if (context.findActivity()?.isChangingConfigurations == true) return@onDispose
            if (session.disappeared()) {
                ShareCardSharing.log(
                    context,
                    ShareCardAction.CANCEL,
                    content.aqi,
                    shape,
                    stationId
                )
            }
        }
    }

    fun finishSave(bitmap: Bitmap, granted: Boolean) {
        val savedShape = shape
        backgroundScope.launch {
            val result = if (granted) {
                withContext(Dispatchers.IO) {
                    ShareCardSharing.saveToPhotos(context, bitmap, ShareCardSharing.fileName(stationId, savedShape))
                }
            } else {
                ShareCardSaveResult.DENIED
            }
            isSaving = false
            saveResult = result
            if (result == ShareCardSaveResult.SAVED) {
                ShareCardSharing.log(context, ShareCardAction.SAVE, content.aqi, savedShape, stationId)
            }
            // The preview may be gone by now: a failed save then ends the session as a cancel.
            if (session.saveFinished(saved = result == ShareCardSaveResult.SAVED)) {
                ShareCardSharing.log(context, ShareCardAction.CANCEL, content.aqi, savedShape, stationId)
            }
        }
    }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val bitmap = image?.asAndroidBitmap()
        if (bitmap == null) {
            isSaving = false
            session.saveFinished(saved = false)
        } else {
            finishSave(bitmap, granted)
        }
    }

    val share = share@{
        val bitmap = image?.asAndroidBitmap() ?: return@share
        session.shared()
        ShareCardSharing.log(context, ShareCardAction.SHARE, content.aqi, shape, stationId)
        val name = ShareCardSharing.fileName(stationId, shape)
        backgroundScope.launch {
            val uri = runCatching {
                withContext(Dispatchers.IO) { ShareCardSharing.writeToCache(context, bitmap, name) }
            }.getOrNull()
            if (uri == null) {
                saveResult = ShareCardSaveResult.FAILED
                return@launch
            }
            val message = ShareCardSharing.message(context, content.title, content.aqi)
            context.startActivitySafely(ShareCardSharing.shareIntent(uri, message, ShareCardSharing.shareText(message)))
        }
    }

    val save = save@{
        val bitmap = image?.asAndroidBitmap() ?: return@save
        if (isSaving) return@save
        isSaving = true
        session.saveStarted()
        if (ShareCardSharing.hasWritePermission(context)) {
            finishSave(bitmap, granted = true)
        } else {
            permission.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                CenterAlignedTopAppBar(
                    title = { Text(stringResource(R.string.share_preview_title)) },
                    navigationIcon = {
                        TextButton(onClick = onDismiss) { Text(stringResource(R.string.share_cancel)) }
                    }
                )
            }
        ) { padding ->
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.TopCenter) {
                // Laid out at the card's own size and density, and recorded rather than drawn.
                ShareCardCapture(content, shape) { image = it }

                Column(
                    // A readable column on a tablet or an unfolded phone.
                    Modifier.widthIn(max = 520.dp).fillMaxSize().padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                        val current = image
                        if (current == null) {
                            CircularProgressIndicator()
                        } else {
                            val description = ShareCardSharing.message(context, content.title, content.aqi)
                            Image(
                                current,
                                contentDescription = null,
                                contentScale = ContentScale.Fit,
                                modifier = Modifier
                                    .aspectRatio(shape.pixelWidth.toFloat() / shape.pixelHeight)
                                    .shadow(8.dp, RoundedCornerShape(12.dp))
                                    .clip(RoundedCornerShape(12.dp))
                                    .semantics { contentDescription = description }
                            )
                        }
                    }

                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        ShareCardShape.entries.forEachIndexed { index, option ->
                            SegmentedButton(
                                selected = option == shape,
                                onClick = {
                                    if (option != shape) {
                                        shape = option
                                        prefs.edit { putString(ShareCardShape.PREFERENCE_KEY, option.raw) }
                                        saveResult = null
                                        image = null
                                    }
                                },
                                shape = SegmentedButtonDefaults.itemShape(index, ShareCardShape.entries.size),
                                label = { Text(stringResource(option.label), maxLines = 1) }
                            )
                        }
                    }

                    Button(
                        onClick = share,
                        enabled = image != null,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp)
                    ) {
                        Icon(
                            painterResource(R.drawable.ic_share),
                            contentDescription = null,
                            modifier = Modifier.size(18.dp)
                        )
                        Text(stringResource(R.string.share_share), modifier = Modifier.padding(start = 8.dp))
                    }

                    OutlinedButton(
                        onClick = save,
                        enabled = image != null && !isSaving,
                        modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp)
                    ) {
                        Icon(
                            painterResource(R.drawable.ic_save),
                            contentDescription = null,
                            modifier = Modifier.size(18.dp)
                        )
                        Text(stringResource(R.string.share_save_to_photos), modifier = Modifier.padding(start = 8.dp))
                    }

                    SaveStatus(saveResult)
                }
            }
        }
    }
}

@Composable
private fun SaveStatus(result: ShareCardSaveResult?) {
    val context = LocalContext.current
    val style = MaterialTheme.typography.bodySmall
    when (result) {
        ShareCardSaveResult.SAVED -> Row(verticalAlignment = Alignment.CenterVertically) {
            val green = rgb(AirStatus.GOOD.color)
            Icon(
                painterResource(R.drawable.ic_check_circle),
                contentDescription = null,
                tint = green,
                modifier = Modifier.size(16.dp)
            )
            Text(
                stringResource(R.string.share_saved),
                style = style,
                color = green,
                modifier = Modifier.padding(start = 6.dp)
            )
        }

        ShareCardSaveResult.DENIED -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(stringResource(R.string.share_save_denied), style = style, color = secondaryText())
            TextButton(onClick = {
                context.startActivitySafely(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", context.packageName, null)
                    )
                )
            }) { Text(stringResource(R.string.share_open_settings), style = style) }
        }

        ShareCardSaveResult.FAILED ->
            Text(stringResource(R.string.share_save_failed), style = style, color = secondaryText())

        null -> Unit
    }
}

/**
 * Lays [content] out at [shape]'s size with [ShareCardShape.RENDER_SCALE] pixels per dp and a font
 * scale of 1, records it into a graphics layer without drawing it on screen, and hands back the
 * bitmap: 1080 px wide on any phone. Takes no space and is hidden from accessibility.
 */
@Composable
private fun ShareCardCapture(content: ShareCardContent, shape: ShareCardShape, onImage: (ImageBitmap) -> Unit) {
    val layer = rememberGraphicsLayer()
    Box(Modifier.size(0.dp).clearAndSetSemantics {}) {
        CompositionLocalProvider(LocalDensity provides Density(ShareCardShape.RENDER_SCALE, fontScale = 1f)) {
            Box(
                Modifier
                    .wrapContentSize(Alignment.TopStart, unbounded = true)
                    // Recorded only: nothing calls `drawLayer(layer)`, which would put it on screen.
                    .drawWithContent {
                        val card = this
                        layer.record { card.drawContent() }
                    }
            ) {
                ShareCard(content, shape)
            }
        }
    }
    LaunchedEffect(content, shape) {
        // Two frames: one to lay the card out at its new shape, one to record it.
        withFrameNanos {}
        withFrameNanos {}
        val captured = layer.toImageBitmap().asAndroidBitmap()
        // A hardware bitmap can't be compressed to PNG on every version; a software copy can.
        val software = if (captured.config == Bitmap.Config.HARDWARE) {
            captured.copy(Bitmap.Config.ARGB_8888, false)
        } else {
            captured
        }
        onImage(software.asImageBitmap())
    }
}

/** Saves outlive the preview, as on iOS, so a save that fails after it closes can still log `cancel`. */
private val backgroundScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

/** The preferences file iOS's defaults map to here (also the map's and the app language's). */
private const val SETTINGS_PREFS = "settings"

private val sessionSaver: Saver<ShareCardSession, Any> = listSaver(
    save = { listOf(it.isCommitted, it.didCancel) },
    restore = { ShareCardSession(isCommitted = it[0], didCancel = it[1]) }
)

private fun Context.findActivity(): Activity? {
    var current: Context? = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return null
}

private fun Context.startActivitySafely(intent: Intent) {
    try {
        startActivity(intent)
    } catch (_: ActivityNotFoundException) {
    }
}
