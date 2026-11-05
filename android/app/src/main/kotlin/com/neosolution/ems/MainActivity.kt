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
                    showNotification(title, body)
                    result.success(true)
                }
                "didOpenFromNotification" -> {
                    val open = pendingOpenNotifications
                    pendingOpenNotifications = false
                    result.success(open)
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

        notifyFlutterIfNeeded()
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
        val open = intent.getBooleanExtra("open_notifications", false) ||
            intent.action == "FLUTTER_NOTIFICATION_CLICK" ||
            extras?.getString("open") == "notifications" ||
            extras?.getString("click_action") == "FLUTTER_NOTIFICATION_CLICK"
        if (open) {
            pendingOpenNotifications = true
        }
    }

    private fun notifyFlutterIfNeeded() {
        if (!pendingOpenNotifications) return
        methodChannel?.invokeMethod("opened", null)
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

    private fun showNotification(title: String, body: String) {
        ensureChannel()
        val tapIntent = Intent(this, MainActivity::class.java).apply {
            action = "FLUTTER_NOTIFICATION_CLICK"
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("open_notifications", true)
            putExtra("open", "notifications")
        }
        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val pendingIntent = PendingIntent.getActivity(
            this,
            title.hashCode(),
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
            NotificationManagerCompat.from(this).notify(title.hashCode(), notification)
        } catch (_: SecurityException) {
            // Notification permission not granted yet.
        }
    }
}
