package com.example.flutter_application_helpvrywhere

import android.accessibilityservice.AccessibilityService
import android.graphics.Rect
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo

/**
 * Reads the UI tree of whatever app the user is currently looking at.
 *
 * We don't react to accessibility events — the service is purely a query
 * endpoint. MainActivity asks for the current tree via [getActiveWindowTree]
 * whenever the AI needs to localize a target element.
 *
 * The static [instance] is the bridge between this OS-managed service and
 * MainActivity. Android starts/stops the service on its own schedule; we
 * just track the latest live instance so the MethodChannel can find it.
 */
class UiTreeAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "UiTreeAccessibility"

        @Volatile
        var instance: UiTreeAccessibilityService? = null
            private set
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "Service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No-op — we query on demand, not on events.
    }

    override fun onInterrupt() {
        Log.d(TAG, "onInterrupt")
    }

    override fun onDestroy() {
        super.onDestroy()
        if (instance === this) instance = null
        Log.d(TAG, "Service destroyed")
    }

    /**
     * Walk the active window's UI tree and return a flat list of
     * interactable / labeled elements with their REAL on-screen pixel
     * bounds. Each entry shape:
     *   {id:Int, text:String?, description:String?, class:String?,
     *    clickable:Bool, x:Int, y:Int, width:Int, height:Int}
     *
     * "id" is the index in the returned list — the caller passes it back
     * after the AI picks an element, and we look it up in this same list
     * to get the bounds.
     *
     * Returns empty list when the service isn't allowed to see the
     * current window (some apps block accessibility for security).
     */
    fun getActiveWindowTree(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        var nextId = 0
        val myPkg = packageName

        fun traverse(node: AccessibilityNodeInfo?) {
            if (node == null) return

            val bounds = Rect()
            node.getBoundsInScreen(bounds)
            val onScreen = bounds.width() > 0 && bounds.height() > 0

            val text = node.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }
            val desc = node.contentDescription?.toString()?.trim()?.takeIf { it.isNotEmpty() }
            val isInteractive =
                node.isClickable || node.isLongClickable || node.isCheckable
            val hasLabel = text != null || desc != null

            if (onScreen && (hasLabel || isInteractive)) {
                out.add(
                    mapOf(
                        "id" to nextId++,
                        "text" to text,
                        "description" to desc,
                        "class" to node.className?.toString()?.substringAfterLast('.'),
                        "clickable" to node.isClickable,
                        "x" to bounds.left,
                        "y" to bounds.top,
                        "width" to bounds.width(),
                        "height" to bounds.height()
                    )
                )
            }

            for (i in 0 until node.childCount) {
                traverse(node.getChild(i))
            }
        }

        // Pick the right window. `rootInActiveWindow` often returns our own
        // (transparent) overlay window when the assistant is running — we'd
        // walk an empty tree. Iterate ALL visible windows and prefer the
        // foreground APPLICATION window that is NOT our own package.
        val winList: List<AccessibilityWindowInfo> = try {
            windows ?: emptyList()
        } catch (e: Exception) {
            Log.e(TAG, "windows query failed", e)
            emptyList()
        }
        Log.d(TAG, "windows count=${winList.size}")

        var chosen: AccessibilityNodeInfo? = null
        for (w in winList) {
            val r = w.root ?: continue
            val pkg = r.packageName?.toString()
            Log.d(TAG, "  window type=${w.type} pkg=$pkg title=${w.title}")
            // TYPE_APPLICATION is what real apps use (launcher counts too).
            // Skip overlays (TYPE_APPLICATION_OVERLAY) and our own package.
            if (w.type == AccessibilityWindowInfo.TYPE_APPLICATION &&
                pkg != null &&
                pkg != myPkg
            ) {
                chosen = r
                Log.d(TAG, "  → picked window pkg=$pkg")
                break
            }
        }

        // Fallbacks: any non-our-package window, then rootInActiveWindow.
        if (chosen == null) {
            for (w in winList) {
                val r = w.root ?: continue
                val pkg = r.packageName?.toString()
                if (pkg != null && pkg != myPkg) {
                    chosen = r
                    Log.d(TAG, "  fallback to non-overlay pkg=$pkg")
                    break
                }
            }
        }
        if (chosen == null) {
            chosen = rootInActiveWindow
            Log.d(TAG, "fallback to rootInActiveWindow pkg=${chosen?.packageName}")
        }

        if (chosen == null) {
            Log.w(TAG, "no usable root window found")
            return emptyList()
        }

        try {
            traverse(chosen)
        } catch (e: Exception) {
            Log.e(TAG, "Tree traversal failed", e)
        }

        Log.d(TAG, "Returning ${out.size} elements (root pkg=${chosen.packageName})")
        return out
    }
}
