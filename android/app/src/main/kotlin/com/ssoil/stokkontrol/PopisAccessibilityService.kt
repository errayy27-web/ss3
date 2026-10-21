package com.ssoil.stokkontrol

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.SystemClock
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/** Captures the visible Cadmus product dialog after an explicit SS OIL scan request. */
class PopisAccessibilityService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private var pending = false
    private var lastCapture = ""
    private var lastCaptureAt = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.packageName?.toString() != "com.mladost.cadmus") return
        val prefs = getSharedPreferences("popis_bridge", MODE_PRIVATE)
        if (!prefs.getBoolean("armed", false) || pending) return
        pending = true
        handler.postDelayed({
            pending = false
            captureVisibleCadmus()
        }, 350)
    }

    private fun captureVisibleCadmus() {
        val prefs = getSharedPreferences("popis_bridge", MODE_PRIVATE)
        if (!prefs.getBoolean("armed", false)) return
        val nodes = mutableListOf<String>()
        fun walk(node: AccessibilityNodeInfo?, depth: Int) {
            if (node == null || depth > 35 || nodes.size >= 300) return
            node.text?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let(nodes::add)
            node.contentDescription?.toString()?.trim()?.takeIf { it.isNotEmpty() }?.let { desc ->
                if (!nodes.contains(desc)) nodes.add(desc)
            }
            for (i in 0 until node.childCount) walk(node.getChild(i), depth + 1)
        }
        walk(rootInActiveWindow, 0)
        val snapshot = nodes.joinToString(" | ")
        if (!Regex("Artikal\\s*ID", RegexOption.IGNORE_CASE).containsMatchIn(snapshot)) return
        val now = SystemClock.elapsedRealtime()
        if (snapshot == lastCapture && now - lastCaptureAt < 2000) return
        lastCapture = snapshot
        lastCaptureAt = now
        prefs.edit().putString("raw_text", snapshot)
            .putLong("capture_id", System.currentTimeMillis())
            .putBoolean("armed", false).commit()
        // Accessibility services can request an activity launch, but OEM/Android restrictions
        // may still prevent automatic foregrounding. The saved capture remains available.
        try {
            val launch = packageManager.getLaunchIntentForPackage(packageName)
            launch?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            if (launch != null) startActivity(launch)
        } catch (_: Exception) { /* capture is saved even if foreground launch is blocked */ }
    }

    override fun onInterrupt() {}
}
