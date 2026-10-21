package dev.photokeeper.photokeeper

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // lib/update.dart downloads the APK into the cache dir; the system installer confirms and replaces this app.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "photokeeper/update").setMethodCallHandler { call, result ->
            val apk = FileProvider.getUriForFile(this, "$packageName.updates", File(call.arguments as String))
            startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(apk, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            result.success(null)
        }
    }
}
