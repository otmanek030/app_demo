package com.example.demo_app // À remplacer par votre package name

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File



class MainActivity: FlutterActivity() {
    private val CHANNEL = "app_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        println("Setting up method channel")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            println("Received method call: ${call.method}")
            when (call.method) {
                "echo" -> {
                    println("Echo method called")
                    result.success("Echo: ${call.arguments}")
                }
                "installApk" -> {
                    try {
                        // Change this line
                        val args = call.arguments as Map<*, *>
                        val apkPath = args["filePath"] as String
                        // Instead of:
                        // val apkPath = call.arguments as String
                        installApk(apkPath)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun installApk(apkPath: String) {
        val file = File(apkPath)
        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file
        )
        
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(installIntent)
    }

    // In MainActivity.kt

}