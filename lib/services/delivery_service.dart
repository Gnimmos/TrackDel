import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DeliveryService {
  static String? baseUrl = dotenv.env['API_URL'];
  static String? CWDbaseUrl = dotenv.env['COORD_API_URL'];

  /// Fetch active deliveries for a given driver
  static Future<List<Map<String, dynamic>>> fetchActiveDeliveries(int driverId) async {
    final url = Uri.parse('$baseUrl/driver/$driverId/active-delivery');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(json);
      } else {
        throw Exception('Failed to fetch deliveries: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error in fetchActiveDeliveries: $e');
      return [];
    }
  }

  


static Future<bool> hasPendingDeliveries(int driverId) async {
  final deliveries = await fetchActiveDeliveries(driverId);
  return deliveries.isNotEmpty;
}

  /// Fetch W4 order details using external order ID
  static Future<Map<String, dynamic>?> fetchOrderDetails(int driverId, String externalOrderId) async {
    final encodedOrderId = Uri.encodeComponent(externalOrderId);
    final url = Uri.parse('$baseUrl/driver/$driverId/delivery-details/$encodedOrderId');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        print('fetchOrderDetails called: ${response.statusCode}');
        return jsonDecode(response.body);
      } else {
        print('⚠️ Failed to fetch order details: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error in fetchOrderDetails: $e');
      return null;
    }
  }

static Future<bool> completeOrder({
  required int orderId,
  required String paymentMethod,
  required double totalAmount,
  required int driverId,
  required int sessionId,
}) async {
  final response = await http.post(
    Uri.parse('$baseUrl/delivery/$orderId/complete'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      "paymentMethod": paymentMethod,
      "totalAmount": totalAmount,
      "driverId": driverId,
      "sessionId": sessionId,
    }),
  );
  return response.statusCode == 200;
}

  /// Mark delivery as completed
  static Future<bool> markAsDelivered(int driverId, int orderId) async {
    final url = Uri.parse('$baseUrl/driver/$driverId/delivered');

    try {
      final response = await http.patch(
        url,
        headers: { 'Content-Type': 'application/json' },
        body: jsonEncode({ 'orderId': orderId }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Error in markAsDelivered: $e');
      return false;
    }
  }
  
static Future<bool> upsertAddress({
    required String externalOrderId,
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.parse('$baseUrl/delivery/upsert-address');
    final body = {
      'external_order_id': externalOrderId,
      'latitude': latitude,
      'longitude': longitude,
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      // Optionally check response content here
      return true;
    } else {
      print('Failed to upsert address: ${response.statusCode} ${response.body}');
      return false;
    }
  }


static Future<Map<String, dynamic>?> fetchDriverStats({
  required int driverId,
  required int sessionId,
}) async {
  final url = Uri.parse('$baseUrl/driver/$driverId/stats?session_id=$sessionId');
  final response = await http.get(url);
  if (response.statusCode == 200) {
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
  return null;
}


  static Future<Map<String, dynamic>?> getRouteInfo({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      print('❌ GOOGLE_MAPS_API_KEY missing in .env');
      return null;
    }

    final url = Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes');

    final body = {
      "origin": {
        "location": {
          "latLng": {
            "latitude": origin.latitude,
            "longitude": origin.longitude
          }
        }
      },
      "destination": {
        "location": {
          "latLng": {
            "latitude": destination.latitude,
            "longitude": destination.longitude
          }
        }
      },
      "travelMode": "DRIVE"
    };

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': apiKey,
          'X-Goog-FieldMask': 'routes.legs.steps,routes.distanceMeters,routes.duration',
        },
        body: jsonEncode(body),
      );

      print('📥 Raw response: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final route = data['routes'][0];
        final leg = data['routes'][0]['legs'][0];
        return {
          'distance': "${(route['distanceMeters'] / 1000).toStringAsFixed(1)} km",
          'duration': "${(int.parse(route['duration'].replaceAll('s', '')) / 60).round()} min",  
          'steps': leg['steps'],      };
      } else {
        print('❌ Directions API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Exception in getRouteInfo: $e');
    }

    return null;
  }

  static Future<Map<String, dynamic>> markAsDeliveredCWD({
  required String externalOrderId,
  required String apiKey,
}) async {
  final String url = '$CWDbaseUrl/MarkOrderAsDelivered';

  final payload = {
    "request": {
      "ExternalOrderId": externalOrderId,
      "ApiKey": apiKey,
    }
  };

  try {
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final result = json['d'] ?? json;
      return {
        'success': result['success'] ?? result['Success'] ?? false,
        'message': result['message'] ?? result['Message'] ?? 'Unknown error',
        ...result,
      };
    } else {
      print('[markAsDeliveredCWD] HTTP error: ${response.statusCode}');
      return {
        'success': false,
        'message': 'HTTP error: ${response.statusCode}',
      };
    }
  } catch (e) {
    print('[markAsDeliveredCWD] Exception: $e');
    return {
      'success': false,
      'message': 'Exception: $e',
    };
  }
}

}
