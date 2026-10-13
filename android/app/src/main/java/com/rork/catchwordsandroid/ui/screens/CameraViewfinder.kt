package com.rork.catchwordsandroid.ui.screens

import android.content.Context
import android.graphics.Bitmap
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.rork.catchwordsandroid.data.ImageTools
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/** Controls handed from the live viewfinder to the screen: shutter and zoom. */
class CameraHandle {
    internal var capture: ImageCapture? = null
    internal var camera: Camera? = null
    internal var context: Context? = null

    val maxZoom: Float get() = camera?.cameraInfo?.zoomState?.value?.maxZoomRatio ?: 1f

    fun setZoom(ratio: Float) {
        camera?.cameraControl?.setZoomRatio(ratio.coerceIn(1f, maxZoom))
    }

    /** Takes a photo and returns it upright, or null when the camera could not take one. */
    suspend fun takePhoto(): Bitmap? {
        val cap = capture ?: return null
        val ctx = context ?: return null
        return suspendCancellableCoroutine { cont ->
            cap.takePicture(ContextCompat.getMainExecutor(ctx), object : ImageCapture.OnImageCapturedCallback() {
                override fun onCaptureSuccess(image: ImageProxy) {
                    val bmp = runCatching { ImageTools.rotate(image.toBitmap(), image.imageInfo.rotationDegrees) }.getOrNull()
                    image.close()
                    if (cont.isActive) cont.resume(bmp)
                }

                override fun onError(exception: ImageCaptureException) {
                    if (cont.isActive) cont.resume(null)
                }
            })
        }
    }
}

/** CameraX live preview bound to the screen's lifecycle. Reports whether a camera exists for `lensFacing`. */
@Composable
fun CameraViewfinder(
    handle: CameraHandle,
    lensFacing: Int,
    onAvailability: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val previewView = remember {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        }
    }
    val capture = remember {
        ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build()
    }

    LaunchedEffect(lensFacing) {
        val provider = providerOf(context)
        val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
        val has = runCatching { provider.hasCamera(selector) }.getOrDefault(false)
        if (!has) {
            onAvailability(false)
            return@LaunchedEffect
        }
        runCatching {
            provider.unbindAll()
            val preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
            handle.camera = provider.bindToLifecycle(owner, selector, preview, capture)
            handle.capture = capture
            handle.context = context
            onAvailability(true)
        }.onFailure { onAvailability(false) }
    }

    DisposableEffect(Unit) {
        onDispose {
            runCatching { ProcessCameraProvider.getInstance(context).get().unbindAll() }
            handle.camera = null
            handle.capture = null
        }
    }

    AndroidView(factory = { previewView }, modifier = modifier)
}

private suspend fun providerOf(context: Context): ProcessCameraProvider = suspendCancellableCoroutine { cont ->
    val future = ProcessCameraProvider.getInstance(context)
    future.addListener({ cont.resume(future.get()) }, ContextCompat.getMainExecutor(context))
}
