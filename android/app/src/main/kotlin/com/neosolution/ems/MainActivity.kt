package com.neosolution.ems

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.neosolution.ems/notifications"
    private val permissionsChannelName = "com.neosolution.ems/permissions"
    private val alertsChannelId = "ems_alerts"

    private var methodChannel: MethodChannel? = null
    private var permissionsChannel: MethodChannel? = null
    private var pendingOpenNotifications = false
    private var pendingNotificationData: Map<String, Any?>? = null

    private val PERMISSION_REQUEST_CODE = 4401
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureOpenFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureOpenFromIntent(intent)
        notifyFlutterIfNeeded()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureChannel()

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureChannel" -> {
                    ensureChannel()
                    result.success(true)
                }
                "show" -> {
                    val title = call.argument<String>("title") ?: "EMS"
                    val body = call.argument<String>("body") ?: ""
                    val notificationId = call.argument<String>("notification_id") ?: call.argument<Int>("id")?.toString()
                    val payload = call.argument<Map<String, Any?>>("data")
                    showNotification(title, body, notificationId, payload)
                    result.success(true)
                }
                "didOpenFromNotification" -> {
                    val open = pendingOpenNotifications
                    pendingOpenNotifications = false
                    val data = pendingNotificationData
                    pendingNotificationData = null
                    val res = mutableMapOf<String, Any?>("opened" to open)
                    if (data != null) {
                        res["data"] = data
                    }
                    result.success(res)
                }
                else -> result.notImplemented()
            }
        }

        val permChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, permissionsChannelName)
        permissionsChannel = permChannel
        permChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermissions" -> {
                    val status = getPermissionsStatus()
                    result.success(status)
                }
                "requestPermissions" -> {
                    if (pendingPermissionResult != null) {
                        result.success(getPermissionsStatus())
                        return@setMethodCallHandler
                    }
                    val needed = getMissingPermissions()
                    if (needed.isEmpty()) {
                        result.success(getPermissionsStatus())
                    } else {
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(this, needed.toTypedArray(), PERMISSION_REQUEST_CODE)
                    }
                }
                "requestCameraPermission" -> {
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.CAMERA), PERMISSION_REQUEST_CODE)
                    }
                }
                "requestLocationPermission" -> {
                    val hasFine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                    val hasCoarse = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
                    if (hasFine && hasCoarse) {
                        result.success(true)
                    } else {
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                            PERMISSION_REQUEST_CODE
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getPermissionsStatus(): Map<String, Boolean> {
        val cameraGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        val locationGranted = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val notificationsGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else {
            NotificationManagerCompat.from(this).areNotificationsEnabled()
        }

        return mapOf(
            "camera" to cameraGranted,
            "location" to locationGranted,
            "notifications" to notificationsGranted
        )
    }

    private fun getMissingPermissions(): List<String> {
        val needed = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.CAMERA)
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                needed.add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        return needed
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val res = pendingPermissionResult
            pendingPermissionResult = null
            res?.success(getPermissionsStatus())
        }
    }

    private fun captureOpenFromIntent(intent: Intent?) {
        if (intent == null) return
        val extras = intent.extras
        val isFcm = extras != null && (
            extras.containsKey("google.message_id") ||
            extras.containsKey("gcm.n.e") ||
            extras.containsKey("from") ||
            extras.getString("open") == "notifications" ||
            extras.getString("click_action") == "FLUTTER_NOTIFICATION_CLICK"
        )
        val open = intent.getBooleanExtra("open_notifications", false) ||
            intent.action == "FLUTTER_NOTIFICATION_CLICK" ||
            isFcm

        if (open) {
            pendingOpenNotifications = true
            val data = mutableMapOf<String, Any?>()
            extras?.keySet()?.forEach { key ->
                val v = extras.get(key)
                if (v != null) {
                    data[key] = v.toString()
                }
            }
            val title = extras?.getString("title")
                ?: extras?.getString("gcm.notification.title")
                ?: extras?.getString("gcm.n.title")
                ?: extras?.getString("google.c.a.c_l")
            val body = extras?.getString("body")
                ?: extras?.getString("gcm.notification.body")
                ?: extras?.getString("gcm.n.body")
                ?: extras?.getString("google.c.a.m_l")
            if (title != null && (!data.containsKey("title") || data["title"]?.toString()?.isEmpty() == true)) {
                data["title"] = title
            }
            if (body != null && (!data.containsKey("body") || data["body"]?.toString()?.isEmpty() == true)) {
                data["body"] = body
            }
            if (intent.action != null) {
                data["action"] = intent.action
            }
            pendingNotificationData = data
        }
    }

    private fun notifyFlutterIfNeeded() {
        if (!pendingOpenNotifications) return
        val data = pendingNotificationData ?: emptyMap<String, Any?>()
        pendingOpenNotifications = false
        pendingNotificationData = null
        runOnUiThread {
            methodChannel?.invokeMethod("opened", data)
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            alertsChannelId,
            "EMS Alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "EMS alerts and notifications"
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }

    private fun showNotification(
        title: String,
        body: String,
        notificationId: String? = null,
        extraData: Map<String, Any?>? = null
    ) {
        ensureChannel()
        val tapIntent = Intent(this, MainActivity::class.java).apply {
            action = "FLUTTER_NOTIFICATION_CLICK"
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("open_notifications", true)
            putExtra("open", "notifications")
            putExtra("title", title)
            putExtra("body", body)
            if (notificationId != null) {
                putExtra("notification_id", notificationId)
            }
            extraData?.forEach { (k, v) ->
                if (v != null) putExtra(k, v.toString())
            }
        }
        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val notifCode = (title + body).hashCode()
        val pendingIntent = PendingIntent.getActivity(
            this,
            notifCode,
            tapIntent,
            pendingFlags,
        )
        val notification = NotificationCompat.Builder(this, alertsChannelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(this).notify(notifCode, notification)
        } catch (_: SecurityException) {
            // Notification permission not granted yet.
        }
    }
}
