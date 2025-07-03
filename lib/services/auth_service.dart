import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = 'http://4.184.202.172:3212/api'; // <- Android Emulator (use your local IP for real device)

static Future<Map<String, dynamic>> login(String phone, String password) async {
  final response = await http.post(
    Uri.parse('$baseUrl/driver/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'phone': phone, 'password': password}),
  );

  if (response.statusCode == 200) {
    final json = jsonDecode(response.body);

    final prefs = await SharedPreferences.getInstance();
    if (json['token'] != null) await prefs.setString('token', json['token']);
    if (json['driver_id'] != null) await prefs.setInt('driver_id', json['driver_id']);
    if (json['company_id'] != null) await prefs.setInt('company_id', json['company_id']);
    if (json['session_id'] != null) await prefs.setInt('session_id', json['session_id']);

    // Return all fields you need at the top level
    return {
      'success': true,
      'driver_id': json['driver_id'],
      'company_id': json['company_id'],
      'token': json['token'],
      'session_id': json['session_id'],
      'can_resume': json['can_resume'],
      'session_active': json['session_active']
    };
  } else {
    final json = jsonDecode(response.body);
    return {'success': false, 'message': json['message'] ?? 'Login failed'};
  }
}

  static const String _logoutUrl = '$baseUrl/driver/logout'; // Change to your backend URL

  static Future<bool> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final driverId = prefs.getInt('driver_id');
    if (driverId == null) return true; // Already logged out locally

    try {
      final response = await http.post(
        Uri.parse(_logoutUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'driver_id': driverId}),
      );
      if (response.statusCode == 200) {
        await prefs.clear(); // Wipe all local session data
        return true;
      } else {
        print('Logout failed: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Logout exception: $e');
      return false;
    }
  }

static Future<Map<String, dynamic>?> resumeSession(int sessionId) async {
  final url = Uri.parse('$baseUrl/driver/session/$sessionId/resume');
  try {
    final response = await http.post(url);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data;
    } else {
      print('❌ Failed to resume session: ${response.statusCode}');
      return null;
    }
  } catch (e) {
    print('❌ Exception in resumeSession: $e');
    return null;
  }
}


}
