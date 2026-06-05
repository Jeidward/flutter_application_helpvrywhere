package com.example.flutter_application_helpvrywhere

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {

    companion object {
        private const val BACKGROUND_CHANNEL = "app/background"
        private const val SCREENSHOT_CHANNEL = "app/screenshot"
        private const val ACCESSIBILITY_CHANNEL = "app/accessibility"
        private const val REQUEST_MEDIA_PROJECTION = 1001
    }

    // ── MediaProjection state ──────────────────────────────────────────────
    private var mediaProjectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var mediaProjectionCallback: MediaProjection.Callback? = null

    // Android 14+ does NOT allow calling createVirtualDisplay() multiple times
    // on the same MediaProjection. So we create ONE VirtualDisplay + ImageReader
    // when permission is granted, and reuse them for every screenshot.
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var screenWidth = 0
    private var screenHeight = 0

    // Pending requests waiting for the permission dialog to resolve
    private var pendingScreenshotResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    // ─────────────────────────────────────────────────────────────────────────
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── moveToBackground ──────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "moveToBackground") {
                    moveTaskToBack(true)
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }

        // ── Screenshot channel ────────────────────────────────────────────
        mediaProjectionManager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Eager permission grant — call this BEFORE the user navigates
                    // to another app, so the dialog appears while we're still in
                    // foreground. Subsequent takeScreenshot calls will then capture
                    // whatever app the user is currently looking at.
                    "requestScreenCapture" -> handleRequestPermission(result)
                    "takeScreenshot" -> handleTakeScreenshot(result)
                    "hasScreenCapturePermission" -> result.success(mediaProjection != null)
                    else -> result.notImplemented()
                }
            }

        // ── Accessibility channel ─────────────────────────────────────────
        //   getUiTree              → List<Map> of visible/interactable elements
        //                            with pixel bounds, or null if service not running
        //   isAccessibilityEnabled → Bool
        //   openAccessibilitySettings → opens system settings page
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACCESSIBILITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getUiTree" -> {
                        val svc = UiTreeAccessibilityService.instance
                        result.success(svc?.getActiveWindowTree())
                    }
                    "isAccessibilityEnabled" -> {
                        result.success(isAccessibilityServiceEnabled())
                    }
                    "openAccessibilitySettings" -> {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Check if THIS app's accessibility service is currently enabled by
     * the user. The system stores the list of enabled services as a
     * colon-separated string in Settings.Secure.
     */
    private fun isAccessibilityServiceEnabled(): Boolean {
        val target = "$packageName/${UiTreeAccessibilityService::class.java.name}"
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabled.split(':').any { it.equals(target, ignoreCase = true) }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Permission flow
    // ─────────────────────────────────────────────────────────────────────────

    private fun handleRequestPermission(result: MethodChannel.Result) {
        if (mediaProjection != null) {
            // Already granted in this session
            result.success(true)
            return
        }
        pendingPermissionResult?.success(false)
        pendingPermissionResult = result

        val intent = mediaProjectionManager!!.createScreenCaptureIntent()
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_MEDIA_PROJECTION)
    }

    private fun handleTakeScreenshot(result: MethodChannel.Result) {
        if (mediaProjection == null) {
            // No permission yet — stash result and prompt
            pendingScreenshotResult?.success(null)
            pendingScreenshotResult = result

            val intent = mediaProjectionManager!!.createScreenCaptureIntent()
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQUEST_MEDIA_PROJECTION)
            return
        }

        // Lazy setup the first time we have a projection
        if (virtualDisplay == null) {
            val ok = setupVirtualDisplay(mediaProjection!!)
            if (!ok) {
                result.success(null)
                return
            }
        }

        captureScreenInternal(result)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Screen capture — set up the virtual display + image reader ONCE.
    // ─────────────────────────────────────────────────────────────────────────

    private fun setupVirtualDisplay(projection: MediaProjection): Boolean {
        try {
            val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getRealMetrics(metrics)

            screenWidth = metrics.widthPixels
            screenHeight = metrics.heightPixels
            val density = metrics.densityDpi

            val reader = ImageReader.newInstance(
                screenWidth, screenHeight, PixelFormat.RGBA_8888, 2
            )
            imageReader = reader

            virtualDisplay = projection.createVirtualDisplay(
                "ScreenCapture",
                screenWidth, screenHeight, density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface, null, null
            )
            return virtualDisplay != null
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "setupVirtualDisplay failed", e)
            imageReader?.close()
            imageReader = null
            return false
        }
    }

    /**
     * Pulls the latest frame from the long-lived ImageReader and converts
     * it to JPEG bytes. The VirtualDisplay keeps producing frames in the
     * background — we just sample the most recent one here.
     */
    private fun captureScreenInternal(result: MethodChannel.Result) {
        val reader = imageReader
        if (reader == null) {
            result.success(null)
            return
        }

        // Small delay so the VirtualDisplay has a chance to render the
        // current frame after the user navigates / the UI updates.
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                val image: Image? = reader.acquireLatestImage()
                if (image == null) {
                    result.success(null)
                    return@postDelayed
                }

                val plane       = image.planes[0]
                val buffer: ByteBuffer = plane.buffer
                val pixelStride = plane.pixelStride
                val rowStride   = plane.rowStride
                val rowPadding  = rowStride - pixelStride * screenWidth

                val bmp = Bitmap.createBitmap(
                    screenWidth + rowPadding / pixelStride,
                    screenHeight,
                    Bitmap.Config.ARGB_8888
                )
                bmp.copyPixelsFromBuffer(buffer)
                image.close()

                val cropped = Bitmap.createBitmap(bmp, 0, 0, screenWidth, screenHeight)
                bmp.recycle()

                val baos = ByteArrayOutputStream()
                cropped.compress(Bitmap.CompressFormat.JPEG, 85, baos)
                cropped.recycle()

                result.success(baos.toByteArray())
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "captureScreenInternal failed", e)
                result.error("SCREENSHOT_ERROR", e.message, null)
            }
        }, 250L)
    }

    override fun onDestroy() {
        super.onDestroy()
        try { virtualDisplay?.release() } catch (_: Exception) {}
        try { imageReader?.close() } catch (_: Exception) {}
        try { mediaProjection?.stop() } catch (_: Exception) {}
        virtualDisplay = null
        imageReader = null
        mediaProjection = null
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Activity result
    // ─────────────────────────────────────────────────────────────────────────

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_MEDIA_PROJECTION) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            // User denied
            pendingPermissionResult?.success(false)
            pendingPermissionResult = null
            pendingScreenshotResult?.success(null)
            pendingScreenshotResult = null
            return
        }

        // Android 14+ needs the mediaProjection foreground service running
        // BEFORE getMediaProjection() is called.
        val serviceIntent = Intent(this, ScreenCaptureService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            @Suppress("DEPRECATION")
            startService(serviceIntent)
        }

        Handler(Looper.getMainLooper()).postDelayed({
            try {
                val proj: MediaProjection? =
                    mediaProjectionManager!!.getMediaProjection(resultCode, data)
                if (proj == null) {
                    pendingPermissionResult?.success(false)
                    pendingPermissionResult = null
                    pendingScreenshotResult?.success(null)
                    pendingScreenshotResult = null
                    return@postDelayed
                }
                mediaProjection = proj

                // Android 14+ requires a callback to be registered before any
                // virtual display is created (otherwise IllegalStateException).
                val cb = object : MediaProjection.Callback() {
                    override fun onStop() {
                        super.onStop()
                        mediaProjection = null
                        mediaProjectionCallback = null
                    }
                }
                proj.registerCallback(cb, Handler(Looper.getMainLooper()))
                mediaProjectionCallback = cb

                // Set up the long-lived virtual display NOW (must happen before
                // any subsequent createVirtualDisplay would be needed — that's
                // forbidden on Android 14+).
                setupVirtualDisplay(proj)

                // Resolve any pending caller
                pendingPermissionResult?.success(true)
                pendingPermissionResult = null

                val pendingShot = pendingScreenshotResult
                pendingScreenshotResult = null
                if (pendingShot != null) {
                    captureScreenInternal(pendingShot)
                }
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "getMediaProjection failed", e)
                pendingPermissionResult?.success(false)
                pendingPermissionResult = null
                pendingScreenshotResult?.success(null)
                pendingScreenshotResult = null
            }
        }, 600L)
    }
}
