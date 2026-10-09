package com.seriassistant.seri

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.app.role.RoleManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.seriassistant.seri/always_on"
    private var seriChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        seriChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        seriChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val intent = Intent(this, SeriWakeService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("WAKE_SERVICE_START_FAILED", error.message, null)
                    }
                }
                "stop" -> {
                    stopService(Intent(this, SeriWakeService::class.java))
                    result.success(true)
                }
                "openSystemSettings" -> {
                    try {
                        val target = call.argument<String>("target") ?: "main"
                        val action = when (target) {
                            "wifi" -> Settings.ACTION_WIFI_SETTINGS
                            "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
                            "display" -> Settings.ACTION_DISPLAY_SETTINGS
                            "notifications" -> Settings.ACTION_NOTIFICATION_SETTINGS
                            "battery" -> Settings.ACTION_BATTERY_SAVER_SETTINGS
                            "app" -> Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                            else -> Settings.ACTION_SETTINGS
                        }
                        val settingsIntent = if (target == "app") Intent(action, android.net.Uri.parse("package:$packageName")) else Intent(action)
                        startActivity(settingsIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("OPEN_SETTINGS_FAILED", error.message, null)
                    }
                }
                "setDefaultAssistant" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val roleManager = getSystemService(RoleManager::class.java)
                            if (roleManager != null && roleManager.isRoleAvailable(RoleManager.ROLE_ASSISTANT)) {
                                startActivity(roleManager.createRequestRoleIntent(RoleManager.ROLE_ASSISTANT))
                            } else startActivity(Intent(Settings.ACTION_VOICE_INPUT_SETTINGS))
                        } else startActivity(Intent(Settings.ACTION_VOICE_INPUT_SETTINGS))
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("ASSISTANT_SETTINGS_FAILED", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        notifyIfWakeDetected(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        notifyIfWakeDetected(intent)
    }

    private fun notifyIfWakeDetected(source: Intent?) {
        if (source?.getBooleanExtra("seri_wake_detected", false) != true) return
        source.removeExtra("seri_wake_detected")
        Handler(Looper.getMainLooper()).postDelayed({ seriChannel?.invokeMethod("wakeDetected", null) }, 500)
    }
}
