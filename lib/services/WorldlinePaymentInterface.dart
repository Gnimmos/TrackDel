// lib/services/WorldlinePaymentInterface.dart
import 'dart:convert';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Channel name must match MainActivity.kt
const _channelName = 'worldline_payment_interface';

/// Worldline intent action constants
class WpiAction {
  static const processTransaction =
      'com.worldline.payment.action.PROCESS_TRANSACTION';
  static const processInformation =
      'com.worldline.payment.action.PROCESS_INFORMATION';
}

/// A helper model to parse WPI results safely.
class WorldlineResult {
  final Map<String, dynamic> raw;
  WorldlineResult(this.raw);

  /// Android activity result (e.g., "OK", "CANCELED")
  String? get resultCode => raw['resultCode']?.toString();

  /// WPI response payload (string) – may be a JSON string.
  String? get response => raw['WPI_RESPONSE']?.toString();

  /// Decoded JSON from WPI_RESPONSE (if present & valid)
  Map<String, dynamic>? get responseJson {
    final s = response;
    if (s == null || s.isEmpty) return null;
    try {
      final j = jsonDecode(s);
      return (j is Map<String, dynamic>) ? j : null;
    } catch (_) {
      return null;
    }
  }

  String? get sessionId => raw['WPI_SESSION_ID']?.toString();

  /// Result per spec: "WPI_RESULT_SUCCESS" / "WPI_RESULT_FAILURE"
  String? get wpiResult {
    final j = responseJson;
    if (j == null) return null;
    final v = j['Result'] ?? j['result'];
    return v?.toString();
  }

  /// Convenience flags – tolerant to variants
  bool get ok => resultCode == 'OK';
  bool get approved {
    if (!ok) return false;
    final r = wpiResult;
    if (r != null) return r == 'WPI_RESULT_SUCCESS' || r == 'SUCCESS';
    // Some environments used plain strings historically:
    final s = response;
    return s == 'APPROVED' || s == 'SUCCESS' || s == 'WPI_RESULT_SUCCESS';
  }

  // Useful fields to log/store (when present)
  String? get paymentSolutionReference =>
      responseJson?['PaymentSolutionReference']?.toString() ??
      responseJson?['paymentSolutionReference']?.toString();

  String? get authorizationCode =>
      responseJson?['AuthorizationCode']?.toString() ??
      responseJson?['authorizationCode']?.toString();

  String? get merchantIdentifier =>
      responseJson?['merchantIdentifier']?.toString();

  String? get terminalIdentifier =>
      responseJson?['terminalIdentifier']?.toString();

  int? get authorizedAmountMinor {
    final v = responseJson?['AuthorizedAmount'] ?? responseJson?['authorizedAmount'];
    if (v == null) return null;
    if (v is int) return v;
    if (v is String && RegExp(r'^\d+$').hasMatch(v)) return int.parse(v);
    return null;
  }

  String? get currency =>
      responseJson?['Currency']?.toString() ??
      responseJson?['currency']?.toString();

  @override
  String toString() => raw.toString();
}

class WorldlinePaymentInterface {
  static const MethodChannel _ch = MethodChannel(_channelName);

  // ---- Low-level bridge ----
  static Future<Map<String, dynamic>> processTransaction({
    String action = WpiAction.processTransaction,
    required Map<String, Object?> extras,
  }) async {
    _ensureAndroid();
    final res = await _ch.invokeMapMethod<String, dynamic>('processTransaction', {
      'action': action,
      'extras': extras,
    });
    return res ?? <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> processInformation({
    String action = WpiAction.processInformation,
    required Map<String, Object?> extras,
  }) async {
    _ensureAndroid();
    final res = await _ch.invokeMapMethod<String, dynamic>('processInformation', {
      'action': action,
      'extras': extras,
    });
    return res ?? <String, dynamic>{};
  }

  // ---- Helpers ----
  static String _sessionId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Accepts "12.99" (major) or "1299" (minor digits only) and returns minor units.
  static int _toMinorUnits(String amount) {
    if (RegExp(r'^\d+$').hasMatch(amount)) return int.parse(amount);
    final parts = amount.split('.');
    final whole = int.parse(parts[0].isEmpty ? '0' : parts[0]);
    final frac = parts.length > 1 ? parts[1].padRight(2, '0').substring(0, 2) : '00';
    return whole * 100 + int.parse(frac);
  }

  // ---- WPI high-level flows ----

  /// Start a **card purchase** via Tap on Mobile (WPI 2.2).
  ///
  /// [amount] may be "12.99" (major) or "1299" (minor). We normalize to minor units.
  /// [currency] is ISO 4217 alpha (e.g., "EUR").
  /// [orderReference] is your order id (recommended; limited charset/length by acquirer).
  /// Optional WPI request fields can be injected via [extraRequestFields] (e.g., {"tipAmount": 100}).
  /// Use [wpiVersion] if your installed ToM requires 2.1; default is "2.2".
  static Future<WorldlineResult> purchase({
    required String amount,
    required String currency,
    required String orderReference,
    Map<String, Object?> extraRequestFields = const {},
    String wpiVersion = '2.2',
  }) async {
    final minor = _toMinorUnits(amount);

    final wpiRequest = <String, Object?>{
      'currency': currency,
      'requestedAmount': minor,
      'reference': orderReference,
      ...extraRequestFields, // e.g. {"tipAmount": 100}
    };

    final extras = <String, Object?>{
      'WPI_SERVICE_TYPE': 'WPI_SVC_PAYMENT',
      'WPI_VERSION': wpiVersion,
      'WPI_SESSION_ID': _sessionId(),
      'WPI_REQUEST': jsonEncode(wpiRequest),
    };

    final map = await processTransaction(extras: extras);
    return WorldlineResult(map);
  }

  /// Reversal/Cancellation of the **last** successful purchase on the terminal.
  /// Requires the `paymentSolutionReference` returned by the original purchase.
  static Future<WorldlineResult> cancelLast({
    required String paymentSolutionReference,
    String? reference,
    String wpiVersion = '2.2',
  }) async {
    final wpiRequest = <String, Object?>{
      'paymentSolutionReference': paymentSolutionReference,
      if (reference != null) 'reference': reference,
    };

    final extras = <String, Object?>{
      'WPI_SERVICE_TYPE': 'WPI_SVC_CANCEL_PAYMENT',
      'WPI_VERSION': wpiVersion,
      'WPI_SESSION_ID': _sessionId(),
      'WPI_REQUEST': jsonEncode(wpiRequest),
    };

    final map = await processTransaction(extras: extras);
    return WorldlineResult(map);
  }

  /// Refund (partial or total) for a previous purchase (not necessarily the last).
  /// Requires `paymentSolutionReference`. If [amount] is omitted, some setups allow full refund.
  static Future<WorldlineResult> refund({
    required String currency,
    required String paymentSolutionReference,
    String? amount, // "5.00" or "500" (minor)
    String? reference,
    String wpiVersion = '2.2',
  }) async {
    final wpiRequest = <String, Object?>{
      'currency': currency,
      'paymentSolutionReference': paymentSolutionReference,
      if (amount != null) 'requestedAmount': _toMinorUnits(amount),
      if (reference != null) 'reference': reference,
    };

    final extras = <String, Object?>{
      'WPI_SERVICE_TYPE': 'WPI_SVC_REFUND',
      'WPI_VERSION': wpiVersion,
      'WPI_SESSION_ID': _sessionId(),
      'WPI_REQUEST': jsonEncode(wpiRequest),
    };

    final map = await processTransaction(extras: extras);
    return WorldlineResult(map);
  }

  static void _ensureAndroid() {
    if (!kIsWeb && !Platform.isAndroid) {
      throw PlatformException(
        code: 'UNSUPPORTED_PLATFORM',
        message: 'Worldline Tap-on-Mobile is Android-only.',
      );
    }
  }
}
