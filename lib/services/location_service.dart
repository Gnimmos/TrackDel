import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class NativeLocationService {
  static const _channel = MethodChannel('com.sunshine.ermis/location');

  static Future<void> startNativeLocationService(int driverId, int companyId) async {
    print('[NativeLocationService] Calling MethodChannel: $driverId/$companyId');
    await _channel.invokeMethod('startLocationService', {
      'driver_id': driverId,
      'company_id': companyId,
    });
  }


  static Future<void> stopNativeLocationService() async {
    await _channel.invokeMethod('stopLocationService');
  }
}

class LocationService {
  // Singleton pattern for easier usage throughout app
  static final LocationService instance = LocationService._internal();
  LocationService._internal();
  static String? baseUrl = dotenv.env['API_URL'];

  final StreamController<int> _streamController = StreamController<int>.broadcast();
  Timer? _timer;
  bool _isTracking = false;
  int _seconds = 0;

  Stream<int> get stream => _streamController.stream;

  // Start tracking periodically every 30s (immediately as well)
  Future<void> startTracking() async {
    if (_isTracking) return;
    _isTracking = true;
    _seconds = 0;

    // Immediate location update
    await _updateLocation();

    // Every 30 seconds after that
    _timer = Timer.periodic(const Duration(seconds: 30), (_) async {
      _seconds += 30;
      await _updateLocation();
      _streamController.sink.add(_seconds); // emit time since tracking started
    });
  }

  Future<void> stopTracking() async {
    _timer?.cancel();
    _isTracking = false;
    _streamController.close();
  }

  // Main function to get location and post to API
  Future<void> _updateLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('[LocationService] Location services are disabled.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('[LocationService] Location permissions are denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('[LocationService] Location permissions are permanently denied');
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Load driver_id and company_id from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getInt('driver_id');
      final companyId = prefs.getInt('company_id');

      if (driverId == null || companyId == null) {
        print('[LocationService] driver_id or company_id not found in prefs');
        return;
      }

      final url = Uri.parse('$baseUrl/driver/location');
      final body = jsonEncode({
        "driver_id": driverId,
        "company_id": companyId,
        "latitude": position.latitude,
        "longitude": position.longitude,
      });

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: body,
      );

      if (response.statusCode == 200) {
        print('[LocationService] Location updated: ${response.body}');
      } else {
        print(
            '[LocationService] Failed to update location: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('[LocationService] Error updating location: $e');
    }
  }

  /// Get a one-time current location
  /// Get a one-time current location
  static Future<Position?> getLiveLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Location services disabled');
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('❌ Location permissions denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ Location permissions permanently denied');
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print('❌ Error getting live location: $e');
      return null;
    }
  }
}
