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
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        /** TrainingForegroundService 回传通知栏按钮动作的入口（onDestroy 置空防泄漏）。 */
        @JvmStatic
        var instance: MainActivity? = null
    }

    private val channelName = "baoji/focus"
    private val updaterChannelName = "baoji/updater"
    private val trainingChannelName = "baoji/training"
    private var dndFilterBeforeTraining: Int? = null
    private var trainingChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        trainingChannel = null
        TrainingForegroundService.actionSink = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // rest_timer 通道要支持勿扰穿透（Flexify 做法，条目 2）：通道的 bypassDnd
        // 只在创建时生效（已存在通道不可改），所以必须在 flutter_local_notifications
        // 的 Dart init 之前由原生先建好；插件随后同 id 创建时只更新名称/描述。
        ensureRestChannel()
        // 训练卡前台服务（条目 1/3）：Dart 推送内容，原生启停；通知栏按钮回传 Dart。
        trainingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, trainingChannelName)
            .apply {
                setMethodCallHandler { call, result ->
                    try {
                        when (call.method) {
                            "start" -> {
                                TrainingForegroundService.start(
                                    this@MainActivity, call.arguments as? Map<*, *>)
                                result.success(null)
                            }
                            "stop" -> {
                                TrainingForegroundService.stop(this@MainActivity)
                                result.success(null)
                            }
                            "setRestChannelBypassDnd" -> {
                                ensureRestChannel()
                                result.success(null)
                            }
                            else -> result.notImplemented()
                        }
                    } catch (e: Exception) {
                        result.error("NATIVE_ERROR", e.message, null)
                    }
                }
                TrainingForegroundService.actionSink = { action ->
                    try {
                        invokeMethod("notifAction", mapOf("action" to action))
                    } catch (_: Exception) {
                        // 引擎销毁/通道断开：丢弃
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "canRequestInstall" -> result.success(canRequestPackageInstalls())
                        "openInstallPermissionSettings" -> {
                            openInstallPermissionSettings()
                            result.success(null)
                        }
                        "installApk" -> {
                            installApk(call.argument<String>("path"))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("NATIVE_ERROR", e.message, null)
                }
            }
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
                        "openDndSettings" -> {
                            openDndAccessSettings()
                            result.success(null)
                        }
                        "openUsageSettings" -> {
                            openUsageAccessSettings()
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
                        "launcherAppsWithIcons" -> result.success(launcherAppsWithIcons())
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

    /** rest_timer 通道：重要性高 + 勿扰穿透（bypassDnd 只在首次创建时生效）。 */
    private fun ensureRestChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val ch = android.app.NotificationChannel(
            "rest_timer", "组间休息提醒", NotificationManager.IMPORTANCE_HIGH
        )
        ch.description = "组间休息结束的提醒（声音+震动，勿扰下穿透）"
        ch.enableVibration(true)
        ch.setBypassDnd(true)
        nm().createNotificationChannel(ch)
    }

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

    // 勿扰访问的授权开关只在系统专属页，应用信息页没有
    private fun openDndAccessSettings() {
        try {
            startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }

    // 使用情况访问同上
    private fun openUsageAccessSettings() {
        try {
            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
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

    // ---- 桌面应用列表（带应用名与图标 PNG 字节，供分心名单列表展示） ----
    private fun launcherAppsWithIcons(): List<Map<String, Any>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val out = mutableListOf<Map<String, Any>>()
        val seen = mutableSetOf<String>()
        for (ri in pm.queryIntentActivities(intent, 0)) {
            val pkg = ri.activityInfo.packageName
            if (pkg == packageName || !seen.add(pkg)) continue
            val label = try {
                ri.loadLabel(pm).toString()
            } catch (e: Exception) {
                pkg
            }
            var icon: ByteArray? = null
            try {
                val d = ri.loadIcon(pm)
                // 统一缩到 64px 左右再压 PNG：列表展示 38dp 足够，控制通道传输量
                val w = if (d.intrinsicWidth in 1..96) d.intrinsicWidth else 64
                val h = if (d.intrinsicHeight in 1..96) d.intrinsicHeight else 64
                val bmp = android.graphics.Bitmap.createBitmap(
                    w, h, android.graphics.Bitmap.Config.ARGB_8888)
                val canvas = android.graphics.Canvas(bmp)
                d.setBounds(0, 0, w, h)
                d.draw(canvas)
                val stream = java.io.ByteArrayOutputStream()
                bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 90, stream)
                icon = stream.toByteArray()
                bmp.recycle()
            } catch (e: Exception) {
                icon = null
            }
            out.add(mapOf(
                "package" to pkg,
                "label" to label,
                "icon" to (icon ?: ByteArray(0)),
            ))
            if (out.size >= 120) break
        }
        out.sortBy { (it["label"] as String).lowercase() }
        return out
    }

    // ---- 应用内自更新安装 ----
    private fun canRequestPackageInstalls(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()

    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !canRequestPackageInstalls()) {
            try {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"))
                )
            } catch (e: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES))
            }
        }
    }

    /** 唤起系统安装器安装缓存目录里的 APK（Android 8+ 需先授权"安装未知应用"）。 */
    private fun installApk(path: String?) {
        if (path == null) return
        val file = File(path)
        if (!file.exists()) return
        if (!canRequestPackageInstalls()) {
            openInstallPermissionSettings()
            return
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }
}
