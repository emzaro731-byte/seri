package com.seriassistant.seri

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.app.role.RoleManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.seriassistant.seri/always_on"
    private var seriChannel: MethodChannel? = null
    private var flutterReady = false
    private var pendingAssistantInvocation = false
    private var pendingWakeDetected = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        seriChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        seriChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    flutterReady = true
                    result.success(true)
                    dispatchPendingInvocation()
                }
                "start" -> {
                    try {
                        // Start only while the activity is visible. Android 12+ restricts
                        // starting microphone foreground services from the background.
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
                "requestBatteryExemption" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val power = getSystemService(PowerManager::class.java)
                            if (power != null && !power.isIgnoringBatteryOptimizations(packageName)) {
                                val request = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = android.net.Uri.parse("package:$packageName")
                                }
                                startActivity(request)
                            } else {
                                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                            }
                        } else {
                            startActivity(Intent(Settings.ACTION_SETTINGS))
                        }
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("BATTERY_SETTINGS_FAILED", error.message, null)
                    }
                }
                "setTimer" -> {
                    try {
                        val seconds = call.argument<Int>("seconds") ?: 0
                        val label = call.argument<String>("label") ?: "Seri timer"
                        if (seconds <= 0) {
                            result.success(false)
                        } else {
                            val timerIntent = Intent(android.provider.AlarmClock.ACTION_SET_TIMER).apply {
                                putExtra(android.provider.AlarmClock.EXTRA_LENGTH, seconds)
                                putExtra(android.provider.AlarmClock.EXTRA_MESSAGE, label)
                                putExtra(android.provider.AlarmClock.EXTRA_SKIP_UI, false)
                            }
                            if (timerIntent.resolveActivity(packageManager) != null) {
                                startActivity(timerIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                result.success(true)
                            } else result.success(false)
                        }
                    } catch (error: Exception) {
                        result.error("SET_TIMER_FAILED", error.message, null)
                    }
                }
                "setReminderAlarm" -> {
                    try {
                        val hour = call.argument<Int>("hour") ?: -1
                        val minute = call.argument<Int>("minute") ?: 0
                        val label = call.argument<String>("label") ?: "Seri reminder"
                        if (hour !in 0..23 || minute !in 0..59) {
                            result.success(false)
                        } else {
                            val alarmIntent = Intent(android.provider.AlarmClock.ACTION_SET_ALARM).apply {
                                putExtra(android.provider.AlarmClock.EXTRA_HOUR, hour)
                                putExtra(android.provider.AlarmClock.EXTRA_MINUTES, minute)
                                putExtra(android.provider.AlarmClock.EXTRA_MESSAGE, label)
                                putExtra(android.provider.AlarmClock.EXTRA_SKIP_UI, false)
                            }
                            if (alarmIntent.resolveActivity(packageManager) != null) {
                                startActivity(alarmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                result.success(true)
                            } else result.success(false)
                        }
                    } catch (error: Exception) {
                        result.error("SET_REMINDER_FAILED", error.message, null)
                    }
                }
                "createCalendarEvent" -> {
                    try {
                        val title = call.argument<String>("title") ?: "Seri event"
                        val begin = call.argument<Long>("beginMillis") ?: 0L
                        val end = call.argument<Long>("endMillis") ?: (begin + 3600000L)
                        val eventIntent = Intent(Intent.ACTION_INSERT).apply {
                            data = android.provider.CalendarContract.Events.CONTENT_URI
                            putExtra(android.provider.CalendarContract.Events.TITLE, title)
                            putExtra(android.provider.CalendarContract.EXTRA_EVENT_BEGIN_TIME, begin)
                            putExtra(android.provider.CalendarContract.EXTRA_EVENT_END_TIME, end)
                        }
                        if (eventIntent.resolveActivity(packageManager) != null) {
                            startActivity(eventIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        } else result.success(false)
                    } catch (error: Exception) {
                        result.error("CREATE_CALENDAR_EVENT_FAILED", error.message, null)
                    }
                }
                "setAlarm" -> {

                    try {
                        val hour = call.argument<Int>("hour") ?: -1
                        val minute = call.argument<Int>("minute") ?: 0
                        val label = call.argument<String>("label") ?: "Seri alarm"
                        if (hour !in 0..23 || minute !in 0..59) {
                            result.success(false)
                        } else {
                            val alarmIntent = Intent(android.provider.AlarmClock.ACTION_SET_ALARM).apply {
                                putExtra(android.provider.AlarmClock.EXTRA_HOUR, hour)
                                putExtra(android.provider.AlarmClock.EXTRA_MINUTES, minute)
                                putExtra(android.provider.AlarmClock.EXTRA_MESSAGE, label)
                                putExtra(android.provider.AlarmClock.EXTRA_SKIP_UI, false)
                            }
                            if (alarmIntent.resolveActivity(packageManager) != null) {
                                startActivity(alarmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                result.success(true)
                            } else result.success(false)
                        }
                    } catch (error: Exception) {
                        result.error("SET_ALARM_FAILED", error.message, null)
                    }
                }
                "openApp" -> {
                    try {
                        val requested = (call.argument<String>("name") ?: "").trim()
                        if (requested.isBlank()) {
                            result.success(false)
                        } else {
                            val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                            val activities = packageManager.queryIntentActivities(launcherIntent, 0)
                            val wanted = requested.lowercase().removePrefix("the ").trim()
                            val match = activities.firstOrNull {
                                it.loadLabel(packageManager).toString().trim().lowercase() == wanted
                            } ?: activities.firstOrNull {
                                val label = it.loadLabel(packageManager).toString().trim().lowercase()
                                label.contains(wanted) || wanted.contains(label)
                            }
                            val launchIntent = match?.activityInfo?.let {
                                packageManager.getLaunchIntentForPackage(it.packageName)
                            }
                            if (launchIntent != null) {
                                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(launchIntent)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        }
                    } catch (error: Exception) {
                        result.error("OPEN_APP_FAILED", error.message, null)
                    }
                }
                "openSystemSettings" -> {
                    try {
                        val target = call.argument<String>("target") ?: "main"
                        val action = when (target) {
                            "wifi" -> Settings.ACTION_WIFI_SETTINGS
                            "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
                            "display" -> Settings.ACTION_DISPLAY_SETTINGS
                            "notifications" -> "android.settings.APP_NOTIFICATION_SETTINGS"
                            "battery" -> Settings.ACTION_BATTERY_SAVER_SETTINGS
                            "location" -> Settings.ACTION_LOCATION_SOURCE_SETTINGS
                            "sound" -> Settings.ACTION_SOUND_SETTINGS
                            "accessibility" -> Settings.ACTION_ACCESSIBILITY_SETTINGS
                            "privacy" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) Settings.ACTION_PRIVACY_SETTINGS else Settings.ACTION_SETTINGS
                            "date_time" -> Settings.ACTION_DATE_SETTINGS
                            "default_apps" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS else Settings.ACTION_SETTINGS
                            "storage" -> Settings.ACTION_INTERNAL_STORAGE_SETTINGS
                            "security" -> Settings.ACTION_SECURITY_SETTINGS
                            "app" -> Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                            "battery_app" -> Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
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
        val launchIntent = source ?: return
        val assistantInvoked = launchIntent.getBooleanExtra("seri_assistant_invoked", false)
        val wakeDetected = launchIntent.getBooleanExtra("seri_wake_detected", false)
        if (!assistantInvoked && !wakeDetected) return
        launchIntent.removeExtra("seri_assistant_invoked")
        launchIntent.removeExtra("seri_wake_detected")
        if (assistantInvoked) pendingAssistantInvocation = true
        if (wakeDetected) pendingWakeDetected = true
        Handler(Looper.getMainLooper()).postDelayed({ dispatchPendingInvocation() }, 250)
    }

    private fun dispatchPendingInvocation() {
        if (!flutterReady || seriChannel == null) return
        when {
            pendingAssistantInvocation -> {
                pendingAssistantInvocation = false
                pendingWakeDetected = false
                seriChannel?.invokeMethod("assistantInvoked", null)
            }
            pendingWakeDetected -> {
                pendingWakeDetected = false
                seriChannel?.invokeMethod("wakeDetected", null)
            }
        }
    }
}
