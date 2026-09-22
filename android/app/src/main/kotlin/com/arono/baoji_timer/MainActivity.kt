package com.arono.baoji_timer

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.PowerManager
import android.provider.Settings
import android.app.usage.UsageStatsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "baoji/focus"
    private var dndFilterBeforeTraining: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "dndGranted" -> result.success(isDndGranted())
                        "dndFilter" -> result.success(currentDndFilter())
                        "setDnd" -> {
                            val on = call.argument<Boolean>("on") ?: false
                            setDnd(on)
                            result.success(null)
                        }
                        "usageGranted" -> result.success(isUsageAccessGranted())
                        "recentUsage" -> {
                            val seconds = (call.argument<Int>("seconds") ?: 90).toLong()
                            val packages = call.argument<List<String>>("packages") ?: emptyList()
                            val hit = recentDistractingUsage(seconds, packages)
                            if (hit == null) result.success(null)
                            else result.success(mapOf("package" to hit.first, "seconds" to hit.second))
                        }
                        "canExactAlarm" -> result.success(canExactAlarm())
                        "openExactAlarmSettings" -> {
                            openExactAlarmSettings()
                            result.success(null)
                        }
                        "ignoringBattery" -> result.success(isIgnoringBattery())
                        "requestIgnoreBattery" -> {
                            requestIgnoreBattery()
                            result.success(null)
                        }
                        "vibrate" -> {
                            val ms = (call.argument<Int>("ms") ?: 120).toLong()
                            vibrate(ms)
                            result.success(null)
                        }
                        "launcherApps" -> result.success(launcherApps())
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("NATIVE_ERROR", e.message, null)
                }
            }
    }

    // ---- 勿扰 ----
    private fun nm(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun isDndGranted(): Boolean =
        nm().isNotificationPolicyAccessGranted

    private fun currentDndFilter(): Int =
        if (isDndGranted()) nm().currentInterruptionFilter else 2

    private fun setDnd(on: Boolean) {
        if (!isDndGranted()) return
        if (on) {
            // 记住训练前的档位，结束时恢复（用户若是"仅闹钟"不应被改成"全部"）
            dndFilterBeforeTraining = nm().currentInterruptionFilter
            nm().setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
        } else {
            val restore = dndFilterBeforeTraining
                ?: NotificationManager.INTERRUPTION_FILTER_ALL
            nm().setInterruptionFilter(restore)
            dndFilterBeforeTraining = null
        }
    }

    // ---- 使用情况访问 ----
    private fun isUsageAccessGranted(): Boolean {
        return try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val now = System.currentTimeMillis()
            val stats = usm.queryAndAggregateUsageStats(now - 60_000L, now)
            stats.isNotEmpty()
        } catch (e: SecurityException) {
            false
        }
    }

    /** 返回 (分心包名, 累计使用秒)：最近 seconds 秒内（排除自己）。 */
    private fun recentDistractingUsage(seconds: Long, packages: List<String>): Pair<String, Int>? {
        if (!isUsageAccessGranted()) return null
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val stats = usm.queryAndAggregateUsageStats(now - seconds * 1000, now)
        var best: Pair<String, Int>? = null
        for ((pkg, usage) in stats) {
            if (pkg == packageName) continue
            if (packages.isNotEmpty() && packages.none { pkg.startsWith(it) || it == pkg }) continue
            val usedMs = usage.totalTimeInForeground
            if (usedMs > 3000) {
                val sec = (usedMs / 1000).toInt()
                if (best == null || sec > best.second) best = pkg to sec
            }
        }
        return best
    }

    // ---- 精确闹钟 ----
    private fun alarmManager(): AlarmManager =
        getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun canExactAlarm(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager().canScheduleExactAlarms()

    private fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                    Uri.parse("package:$packageName")))
            } catch (e: Exception) {
                startActivity(Intent(Settings.ACTION_SETTINGS))
            }
        }
    }

    // ---- 电池优化 ----
    private fun isIgnoringBattery(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBattery() {
        if (isIgnoringBattery()) return
        try {
            startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName")))
        } catch (e: Exception) {
            // 部分ROM不支持，忽略
        }
    }

    // ---- 震动 ----
    private fun vibrate(ms: Long) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager
            vm.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(ms)
        }
    }

    // ---- 桌面应用列表（供选择分心 App） ----
    private fun launcherApps(): List<String> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(intent, 0)
            .map { it.activityInfo.packageName }
            .distinct()
            .sorted()
    }
}
