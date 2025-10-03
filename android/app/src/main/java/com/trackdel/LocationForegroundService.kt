package com.ermis

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.location.Location
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import android.util.Log
import com.google.android.gms.location.*
import kotlinx.coroutines.*
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import android.os.Looper

class LocationForegroundService : Service() {

    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var notificationManager: NotificationManager
    private var job: Job? = null

    override fun onCreate() {
        super.onCreate()
        Log.i("LocationService", "Service CREATED")
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i("LocationService", "Service STARTED")
        startForeground(1, createNotification())

        val driverId = intent?.getIntExtra("driver_id", -1) ?: -1
        val companyId = intent?.getIntExtra("company_id", -1) ?: -1

        Log.i("LocationService", "Tracking driverId=$driverId, companyId=$companyId")

        job = CoroutineScope(Dispatchers.IO).launch {
            while (true) {
                Log.d("LocationService", "Loop: request location")
                getLocationAndSend(driverId, companyId)
                delay(30_000)
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        job?.cancel()
        Log.i("LocationService", "Service DESTROYED")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun getLocationAndSend(driverId: Int, companyId: Int) {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            Log.d("LocationService", "Location permission GRANTED")
            val locationRequest = LocationRequest.create().apply {
                interval = 10000
                fastestInterval = 5000
                priority = LocationRequest.PRIORITY_HIGH_ACCURACY
                numUpdates = 1
            }
            Log.d("LocationService", "Requesting location update")
            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                object : LocationCallback() {
                    override fun onLocationResult(result: LocationResult) {
                        val location = result.lastLocation
                        Log.d("LocationService", "onLocationResult called")
                        if (location != null) {
                            Log.i("LocationService", "Location result: ${location.latitude}, ${location.longitude}")
                            // Run the network call off the main thread!
                            CoroutineScope(Dispatchers.IO).launch {
                                Log.d("LocationService", "Launching sendLocationToServer in IO dispatcher")
                                sendLocationToServer(driverId, companyId, location.latitude, location.longitude)
                            }
                        } else {
                            Log.w("LocationService", "Location is NULL")
                        }
                        fusedLocationClient.removeLocationUpdates(this)
                    }

                    override fun onLocationAvailability(availability: LocationAvailability) {
                        Log.d("LocationService", "LocationAvailability: ${availability.isLocationAvailable}")
                    }
                },
                Looper.getMainLooper()
            )
        } else {
            Log.e("LocationService", "Location permission DENIED")
        }
    }
        private fun sendLocationToServer(driverId: Int, companyId: Int, lat: Double, lon: Double) {
            Log.d("LocationService", "Sending to server: driverId=$driverId, companyId=$companyId, lat=$lat, lon=$lon")
            try {
                val url = URL("http://4.184.202.172:3016/api/driver/location")
                val conn = url.openConnection() as HttpURLConnection
                conn.connectTimeout = 10000
                conn.readTimeout = 10000
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                conn.setRequestProperty("Accept", "application/json")
                conn.doOutput = true
                conn.doInput = true
                val json = """
                    {
                    "driver_id": $driverId,
                    "company_id": $companyId,
                    "latitude": $lat,
                    "longitude": $lon
                    }
                """.trimIndent()
                Log.d("LocationService", "Sending JSON: $json")

                // Write the JSON string using DataOutputStream
                conn.outputStream.use { os ->
                    val input = json.toByteArray(Charsets.UTF_8)
                    os.write(input, 0, input.size)
                    os.flush()
                }

                val responseCode = conn.responseCode
                val response = conn.inputStream.bufferedReader().use { it.readText() }
                Log.i("LocationService", "Location sent: $json, Response: $responseCode, Body: $response")
            } catch (e: Exception) {
                Log.e("LocationService", "Failed to send location", e)
            }
        }


    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "ermis_channel",
                "ermis Background Location",
                NotificationManager.IMPORTANCE_LOW
            )
            notificationManager.createNotificationChannel(channel)
            Log.d("LocationService", "Notification channel created")
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, "ermis_channel")
            .setContentTitle("ermis")
            .setContentText("Tracking location in background")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .build()
    }
}
