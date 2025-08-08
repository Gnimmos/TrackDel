import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AuthService {
  static String? baseUrl = dotenv.env['API_URL'];
  static String? CWDbaseUrl = dotenv.env['COORD_API_URL'];

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
    if (json['w4_company_code'] != null) await prefs.setString('w4_company_code', json['w4_company_code']);

    // Return all fields you need at the top level
    return {
      'success': true,
      'driver_id': json['driver_id'],
      'company_id': json['company_id'],
      'w4_company_code': json['w4_company_code'],
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

  static final String _logoutUrl = '$baseUrl/driver/logout'; 

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
    static Future<Map<String, dynamic>> loginCoordinatorQWD(
      
        String mobile, String password, String apiKey) async {
      final String coordinatorUrl =
          '$CWDbaseUrl/DriverLogin';

      //String hashedPassword = BCrypt.hashpw(password, BCrypt.gensalt());
    

      // Create the request payload
      final payload = {
        'request': {
          'Mobile': mobile,
          'Password': password,
          'ApiKey': apiKey,
        },
      };

      print('[QWD] Sending to coordinator: ${jsonEncode(payload)}'); // LOG what you send

      final response = await http.post(
        Uri.parse(coordinatorUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      print('[QWD] Raw response (${response.statusCode}): ${response.body}'); // LOG raw response

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        // Unwrap "d" property for actual result
        final result = json['d'] ?? {};

        print('[QWD] Decoded result: $result'); // LOG decoded 'd' property

        return {
          'success': result['success'] ?? result['Success'] ?? false,
          'message': result['message'] ?? result['Message'] ?? 'Unknown error',
          ...result,
        };
      } else {
        try {
          final json = jsonDecode(response.body);
          print('[QWD] Error response JSON: $json'); // LOG error response
          return {
            'success': false,
            'message': json['message'] ?? 'Login failed',
          };
        } catch (_) {
          print('[QWD] Error decoding error response!'); // LOG catch
          return {
            'success': false,
            'message': 'Login failed: HTTP ${response.statusCode}',
          };
        }
      }
    }
 static Future<List<dynamic>?> fetchOutletsForCompany() async {
    final prefs = await SharedPreferences.getInstance();
    final companyId = prefs.getInt('company_id');

    if (companyId == null) {
      print('No company_id found in shared preferences.');
      return null;
    }

    final url = Uri.parse('$baseUrl/company/$companyId/outlets');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Assuming your API returns a JSON array or {success, outlets: [..]}
        // Adjust based on your backend response
        return data['outlets'] ?? data; 
      } else {
        print('Failed to fetch outlets: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Exception fetching outlets: $e');
      return null;
    }
  }
  static Future<List<dynamic>?> getOutletsByCompanyId(int companyId) async {
      final url = Uri.parse('$baseUrl/company/$companyId/outlets');
      try {
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is Map && data['success'] == true && data['data'] is List) {
            return data['data'];
          } else {
            print('Unexpected response format: $data');
            return null;
          }
        } else {
          print('Failed to fetch outlets: ${response.body}');
          return null;
        }
      } catch (e) {
        print('Exception fetching outlets: $e');
        return null;
      }
    }

  static Future<Map<String, dynamic>> setDriverActiveOutlet({
    required String mobile,
    required String w4CompanyCode,
    required String outletName,
    required String apiKey,
  }) async {
    final String url = '$CWDbaseUrl/SetDriverActiveOutlet';

    final payload = {
      "request": {
        "Mobile": mobile,
        "W4CompanyCode": w4CompanyCode,
        "OutletName": outletName,
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
        // The actual result may be wrapped in 'd', like other coordinator APIs
        final result = json['d'] ?? json;
        return {
          'success': result['success'] ?? result['Success'] ?? false,
          'message': result['message'] ?? result['Message'] ?? 'Unknown error',
          ...result,
        };
      } else {
        print('[SetDriverActiveOutlet] HTTP error: ${response.statusCode}');
        return {
          'success': false,
          'message': 'HTTP error: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('[SetDriverActiveOutlet] Exception: $e');
      return {
        'success': false,
        'message': 'Exception: $e',
      };
    }
  }

  static Future<Map<String, dynamic>?> fetchLastOutlet({String? phone}) async {
    final params = <String, String>{};
    if (phone != null) params['phone'] = phone;

    final uri = Uri.parse('$baseUrl/company/lastoutlet').replace(queryParameters: params);

    print('Calling: $uri'); // For debug

    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true && data['outlet'] != null) {
        return data['outlet'] as Map<String, dynamic>;
      }
      return null;
    } else {
      throw Exception('Failed to fetch last outlet');
    }
  }


}
