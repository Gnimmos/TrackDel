package com.trackdel

import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.trackdel/location"
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i("TrackDel", "MAINACTIVITY onCreate CALLED!")
       
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.i("TrackDel", "configureFlutterEngine CALLED!")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startLocationService" -> {
                    val driverId = call.argument<Int>("driver_id") ?: -1
                    val companyId = call.argument<Int>("company_id") ?: -1
                    val intent = Intent(this, LocationForegroundService::class.java)
                    intent.putExtra("driver_id", driverId)
                    intent.putExtra("company_id", companyId)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopLocationService" -> {
                    stopService(Intent(this, LocationForegroundService::class.java))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
