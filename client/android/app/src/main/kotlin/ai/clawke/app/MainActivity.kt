package ai.clawke.app

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val pushPermissionRequestCode = 4107
    private var pendingPushRegistrationResult: MethodChannel.Result? = null
    private var pushChannel: MethodChannel? = null
    private var pushChannelReady = false
    private val pendingRemotePushPayloads = mutableListOf<Map<String, Any>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "clawke/app_badge"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setBadgeCount" -> result.success(null)
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(null)
                }
                "checkNotificationsEnabled" -> {
                    result.success(areNotificationsEnabled())
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "clawke/push"
        ).also { channel ->
            pushChannel = channel
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "registerForRemoteNotifications" -> registerForRemoteNotifications(result)
                    "readStableDeviceId" -> result.success(readStablePushDeviceId())
                    "takeRemotePushPayloads" -> {
                        val payloads = pendingRemotePushPayloads.toList()
                        pendingRemotePushPayloads.clear()
                        pushChannelReady = true
                        result.success(payloads)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        deliverRemotePushIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverRemotePushIntent(intent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != pushPermissionRequestCode) return
        val result = pendingPushRegistrationResult ?: return
        pendingPushRegistrationResult = null
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            result.error("notification_permission_denied", "Android notification permission denied.", null)
            return
        }
        fetchFcmToken(result)
    }

    private fun readStablePushDeviceId(): String {
        val androidId = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ANDROID_ID
        ).orEmpty()
        if (androidId.isNotBlank() && androidId != "9774d56d682e549c") {
            return "android-${sha256Hex("$packageName:$androidId").take(32)}"
        }

        val prefs = getSharedPreferences("clawke_push", MODE_PRIVATE)
        val existing = prefs.getString("stable_device_id", null)
        if (!existing.isNullOrBlank()) return existing
        val generated = "android-${UUID.randomUUID()}"
        prefs.edit().putString("stable_device_id", generated).apply()
        return generated
    }

    private fun sha256Hex(value: String): String {
        val bytes = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }
        }
        startActivity(intent)
    }

    private fun areNotificationsEnabled(): Boolean {
        val permissionGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        val managerEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            getSystemService(NotificationManager::class.java).areNotificationsEnabled()
        } else {
            true
        }
        return permissionGranted && managerEnabled
    }

    private fun registerForRemoteNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingPushRegistrationResult != null) {
                result.error("push_registration_in_progress", "Push registration already in progress.", null)
                return
            }
            pendingPushRegistrationResult = result
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                pushPermissionRequestCode
            )
            return
        }
        fetchFcmToken(result)
    }

    private fun fetchFcmToken(result: MethodChannel.Result) {
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (!task.isSuccessful) {
                result.error(
                    "fcm_token_failed",
                    task.exception?.message ?: "FCM token request failed.",
                    null
                )
                return@addOnCompleteListener
            }
            val token = task.result.orEmpty()
            if (token.isBlank()) {
                result.error("fcm_token_empty", "FCM token is empty.", null)
                return@addOnCompleteListener
            }
            result.success(
                mapOf(
                    "token" to token,
                    "platform" to "android",
                    "push_provider" to "fcm"
                )
            )
        }
    }

    private fun deliverRemotePushIntent(intent: Intent?) {
        val payload = remotePushPayloadFromIntent(intent) ?: return
        if (pushChannelReady) {
            pushChannel?.invokeMethod("remotePushReceived", payload)
        } else {
            pendingRemotePushPayloads.add(payload)
        }
    }

    private fun remotePushPayloadFromIntent(intent: Intent?): Map<String, Any>? {
        val extras = intent?.extras ?: return null
        val conversationId = extras.getString("conversation_id").orEmpty()
        val messageId = extras.getString("message_id").orEmpty()
        val gatewayId = extras.getString("gateway_id").orEmpty()
        if (conversationId.isBlank() || messageId.isBlank() || gatewayId.isBlank()) return null
        val seqValue = extras.get("seq")
        val seq = when (seqValue) {
            is Number -> seqValue.toInt()
            is String -> seqValue.toIntOrNull() ?: 0
            else -> 0
        }
        return mapOf(
            "conversation_id" to conversationId,
            "message_id" to messageId,
            "gateway_id" to gatewayId,
            "seq" to seq,
            "event_type" to "notification_tap"
        )
    }
}
