// android/app/src/main/kotlin/com/ermis/MainActivity.kt
package com.ermis

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // Existing channel for your location service
    private val LOCATION_CHANNEL = "com.ermis/location"

    // Payment channel name (must match your Dart)
    private val PAYMENT_CHANNEL = "worldline_payment_interface"

    // Request codes for Worldline flows
    private val REQ_WPI_TRANSACTION = 0x39A1
    private val REQ_WPI_INFO = 0x39A2

    // (Optional) If your acquirer mandates the exact Tap-on-Mobile package, set it here.
    // private val WORLDLINE_PACKAGE = "com.worldline.taponmobile"
    private val WORLDLINE_PACKAGE: String? = null

    // Track pending call so we can return the result once the activity finishes
    private var pendingResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i("ermis", "MAINACTIVITY onCreate CALLED!")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.i("ermis", "configureFlutterEngine CALLED!")

        // ---- LOCATION CHANNEL (unchanged) ----
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL)
            .setMethodCallHandler { call, result ->
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

        // ---- WORLDLINE PAYMENT CHANNEL ----
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PAYMENT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "processTransaction" -> {
                        val action = call.argument<String>("action")
                            ?: "com.worldline.payment.action.PROCESS_TRANSACTION"
                        // Tolerant to any value types from Dart; we will stringify them.
                        val extrasAny = call.argument<Map<String, Any?>>("extras") ?: emptyMap()
                        launchWorldlineIntent(action, extrasAny, REQ_WPI_TRANSACTION, result)
                    }
                    "processInformation" -> {
                        val action = call.argument<String>("action")
                            ?: "com.worldline.payment.action.PROCESS_INFORMATION"
                        val extrasAny = call.argument<Map<String, Any?>>("extras") ?: emptyMap()
                        launchWorldlineIntent(action, extrasAny, REQ_WPI_INFO, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun launchWorldlineIntent(
        action: String,
        extras: Map<String, Any?>,
        requestCode: Int,
        result: MethodChannel.Result
    ) {
        if (pendingResult != null) {
            result.error("BUSY", "Another payment is in progress", null)
            return
        }
        try {
            val intent = Intent(action)

            // (Optional) lock to Worldline package if you know it
            WORLDLINE_PACKAGE?.let { intent.setPackage(it) }

            // Pass all extras to Worldline, stringifying values to avoid ClassCast issues
            for ((k, v) in extras) {
                intent.putExtra(k, v?.toString())
            }

            // Verify there is an app that can handle this intent
            if (intent.resolveActivity(packageManager) == null) {
                result.error(
                    "NO_HANDLER",
                    "Worldline app not installed or action unsupported",
                    null
                )
                return
            }

            // Launch and keep the result callback
            @Suppress("DEPRECATION")
            run {
                startActivityForResult(intent, requestCode)
            }
            pendingResult = result
        } catch (e: ActivityNotFoundException) {
            result.error("NO_HANDLER", "Worldline app not found", e.localizedMessage)
        } catch (e: Exception) {
            result.error("FAILED_TO_START", "Failed to start payment intent", e.localizedMessage)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQ_WPI_TRANSACTION || requestCode == REQ_WPI_INFO) {
            val res = pendingResult
            pendingResult = null

            if (res == null) return

            val out = HashMap<String, Any?>()
            out["resultCode"] = when (resultCode) {
                Activity.RESULT_OK -> "OK"
                Activity.RESULT_CANCELED -> "CANCELED"
                else -> resultCode.toString()
            }

            // Return all extras from Worldline to Flutter
            val extras = data?.extras
            if (extras != null) {
                for (key in extras.keySet()) {
                    val v = extras.get(key)
                    out[key] = when (v) {
                        is String, is Int, is Long, is Double, is Float, is Boolean -> v
                        else -> v?.toString()
                    }
                }
            }

            res.success(out)
        }
    }
}
