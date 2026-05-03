package ai.clawke.app

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
}
