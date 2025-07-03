import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackdel/services/location_service.dart' as LocService;
import 'package:trackdel/services/delivery_service.dart' as DelServ;
import 'package:trackdel/services/auth_service.dart' as Auth;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:trackdel/helpers/miui_autostart_helper.dart' ;
import 'package:trackdel/helpers/location_permission_helper.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

class PendingDeliveriesScreen extends StatefulWidget {
  const PendingDeliveriesScreen({super.key});

  @override
  State<PendingDeliveriesScreen> createState() => _PendingDeliveriesScreenState();
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

class _PendingDeliveriesScreenState extends State<PendingDeliveriesScreen> {
  LatLng? driverLocation;
  List<Map<String, dynamic>> deliveries = [];
  String formattedDate = '';
  String formattedTime = '';
  bool isLoading = true;
  String? etaText;
  String? distanceText;
  List<LatLng> routePoints = [];
  final FlutterTts flutterTts = FlutterTts();
  late PageController _pageController;
  int currentPage = 0;
  Set<int> loadedW4 = {}; // To cache which orders already have W4 data
  Map<int, GoogleMapController> _mapControllers = {};
  Set<int> _mapAnimatedPages = {};  
  final locationService = LocService.LocationService.instance;
  Timer? _autoRefreshTimer;
  GoogleMapController? _mapController;
  Map<String, dynamic>? driverStats;
final Map<String, Map<String, dynamic>> _w4Cache = {};

  @override
  void initState() {
    super.initState();

    _pageController = PageController();
  _fetchDriverStats();

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await MIUIAutostartHelper.showIfNeeded(context);
bool allowed = false;
  while (!allowed) {
    allowed = await LocationPermissionHelper.ensureLocationPermissions(context);
    if (!allowed) {
      // Prompt the user to try again or cancel
      bool tryAgain = await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text("Location Permission Required"),
          content: Text("TrackDel needs location permission (Allow all the time) to track deliveries. Please grant permission to continue."),
          actions: [
            TextButton(
              child: Text("Try Again"),
              onPressed: () => Navigator.of(context).pop(true),
            ),
            TextButton(
              child: Text("Cancel"),
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      );
      if (!tryAgain) {
        print('[Permission] NOT granted, background tracking will NOT start');
        return; // User gave up—stop here!
      }
    }
  }

    // Explicit permission request before starting background tracking
    if (allowed) {
      print('[Permission] granted, starting background tracking');
      _startBackgroundTracking();

     // locationService.startTracking();
        //await LocService.LocationService.startBackgroundTracking();
    } else {
      print('[Permission] NOT granted, background tracking will NOT start');
    }
    _fetchDeliveries(showSpinner: true);
    _updateDateTime();
    _startClock();
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  });
}

  Future<void> _showNewDeliveryNotification() async {
    // Vibrate device if possible
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 1000); // vibrate for 500ms
    }

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'new_delivery_channel',
          'New Deliveries',
          channelDescription: 'Notification for new deliveries',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
        );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      'New Delivery',
      'You have received a new delivery!',
      platformChannelSpecifics,
      payload: 'new_delivery',
    );
  }


  void _updateDateTime() {
    final now = DateTime.now();
    formattedDate = '${_weekdayName(now.weekday)} ${now.day.toString().padLeft(2, '0')} ${_monthName(now.month)}';
    formattedTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {});
  }

  void _startClock() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      _updateDateTime();
      return true;
    });
  }

  String _weekdayName(int weekday) {
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return days[weekday - 1];
  }

  String _monthName(int month) {
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ];
    return months[month - 1];
  }

  List<LatLng> extractRouteFromSteps(List<dynamic> steps) {
    List<LatLng> points = [];
    for (var step in steps) {
      final start = step['startLocation']?['latLng'];
      final end = step['endLocation']?['latLng'];
      if (start != null) {
        points.add(LatLng(start['latitude'], start['longitude']));
      }
      if (end != null) {
        points.add(LatLng(end['latitude'], end['longitude']));
      }
    }
    return points;
  }
  
  Future<void> _startBackgroundTracking() async {
    final prefs = await SharedPreferences.getInstance();
    final driverId = prefs.getInt('driver_id');
    final companyId = prefs.getInt('company_id');
    if (driverId != null && companyId != null) {
      try {
        await LocService.NativeLocationService.startNativeLocationService(driverId, companyId);
        print('[PendingDeliveriesScreen] Native background tracking started');
      } catch (e, stack) {
        print('[NativeLocationService][ERROR] $e');
        print(stack);
      }      
    } else {
      print('[PendingDeliveriesScreen] driver_id or company_id not found');
    }
  }

Future<void> _fetchDriverStats() async {
  final prefs = await SharedPreferences.getInstance();
  final driverId = prefs.getInt('driver_id');
  final sessionId = prefs.getInt('session_id');
  if (driverId == null || sessionId == null) return;
  final stats = await DelServ.DeliveryService.fetchDriverStats(driverId: driverId, sessionId: sessionId);
  setState(() {
    driverStats = stats;
  });
}
  Future<void> _speakInstruction(String instruction) async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.speak(instruction);
  }

  Future<void> _fetchDeliveries({bool showSpinner = true}) async {
  if (showSpinner && mounted) {
    setState(() {
      isLoading = true;
      loadedW4.clear();
    });
  }
  print('_fetchDeliveries called');

  final prefs = await SharedPreferences.getInstance();
  final driverId = prefs.getInt('driver_id');
  if (driverId == null) {
    if (mounted) setState(() => isLoading = false);
    return;
  }

  final prevIds = deliveries.map((d) => d['external_order_id']).toSet();
  final fetchedDeliveries = await DelServ.DeliveryService.fetchActiveDeliveries(driverId);
  final newOnes = fetchedDeliveries.where((d) => !prevIds.contains(d['external_order_id'])).toList();

  if (newOnes.isNotEmpty) {
    await _showNewDeliveryNotification();
  }
  _startAutoRefresh();

  // ---- RESTORE W4 DATA FROM CACHE ----
  for (var delivery in fetchedDeliveries) {
    final orderId = delivery['external_order_id'];
    if (orderId != null && _w4Cache.containsKey(orderId)) {
      final cache = _w4Cache[orderId]!;
      delivery['total_with_taxes'] = cache['total_with_taxes'];
      delivery['items'] = cache['items'];
    }
  }
  // Optionally, clean cache for completed deliveries (removed from fetchedDeliveries)
  final activeIds = fetchedDeliveries.map((d) => d['external_order_id']).toSet();
  _w4Cache.removeWhere((key, value) => !activeIds.contains(key));
  // ------------------------------------

  deliveries = fetchedDeliveries;

    if (deliveries.isEmpty) {
      if (mounted) setState(() {
        currentPage = 0;
        isLoading = false;
      });
      return;
    }

    if (currentPage >= deliveries.length || currentPage != 0) {
      _pageController.jumpToPage(0);
      if (mounted) setState(() {
        currentPage = 0;
        isLoading = false;
      });
    } else {
      if (mounted) setState(() {
        isLoading = false;
      });
    }

  final pos = await LocService.LocationService.getLiveLocation();
  if (pos != null) {
    driverLocation = LatLng(pos.latitude, pos.longitude);
  }

  // Prefetch W4 data for the first delivery only
await Future.wait([for (int i = 0; i < deliveries.length; i++) _fetchW4AndRoute(i)]);

  if (showSpinner && mounted) setState(() => isLoading = false);
}


  @override
void dispose() {
  _autoRefreshTimer?.cancel();
  _pageController.dispose();
  super.dispose();
}

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel(); // Prevent multiple timers
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
    _fetchDeliveries(showSpinner: false);
    });
  }

  Future<void> _fetchW4AndRoute(int index) async {
    if (index < 0 || index >= deliveries.length) return;
    final delivery = deliveries[index];
    print("_fetchW4AndRoute called");

    // Fetch W4 only if not already loaded
    if (!(loadedW4.contains(index))) {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getInt('driver_id');
      if (driverId != null && delivery['external_order_id'] != null) {
        final w4Data = await DelServ.DeliveryService.fetchOrderDetails(driverId, delivery['external_order_id']);
        if (w4Data != null) {
          try {
            final docs = w4Data['data']?['Data']?['Documents'];
            if (docs != null && docs is List && docs.isNotEmpty) {
              final doc = docs[0];
              final total = doc['TotalWithTaxes'];
              delivery['total_with_taxes'] = (total is num) ? total.toStringAsFixed(2) : '0.00';
              final items = doc['Details'];
              if (items != null && items is List) {
                delivery['items'] = items;
              }
              final orderId = delivery['external_order_id'];
              if (orderId != null) {
               _w4Cache[orderId] = {
                'total_with_taxes': delivery['total_with_taxes'],
                'items': delivery['items'],
            };
          }
            }
          } catch (e) {
            print("❌ Exception parsing W4 order details: $e");
          }
        }
        loadedW4.add(index);
      }
    }
  if (delivery['latitude'] != null && delivery['longitude'] != null && _mapController != null) {
    _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(delivery['latitude'], delivery['longitude']),
        17.0,
      ),
    );
  }
}

Widget _buildStatsBlock() {
  if (driverStats == null) {
    return const SizedBox.shrink();
  }

  final stats = [
    {'label': 'Float',     'type': 'euro',  'value': driverStats!['initial_cash'] },
    {'label': 'Delivered', 'type': 'count', 'value': driverStats!['total_deliveries'] },
    {'label': 'Cashed Out',  'type': 'euro',  'value': driverStats!['cash_out'] },
    {'label': 'Visa',      'type': 'euro',  'value': driverStats!['visa_collected'] },
    {'label': 'Cash',      'type': 'euro',  'value': driverStats!['cash_collected'] },
    {'label': 'To Return',  'type': 'euro',  'value': driverStats!['returned'] },
  ];

  while (stats.length < 6) {
    stats.add({'label': '', 'value': '', 'type': 'none'});
  }

  return Card(
    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8), // Even smaller margins
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    elevation: 1,
    child: Container(
      height: 120,
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 1),       
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        childAspectRatio: 2,
        children: stats.map((stat) {
          final label = stat['label'] as String;
          final value = stat['value'];
          final type = stat['type'] as String;

          String displayValue = value == null || value.toString().isEmpty ? '-' : value.toString();
          if (type == 'euro' && displayValue != '-') {
            double? val = double.tryParse(value.toString());
            displayValue = '€ ${val != null ? val.toStringAsFixed(2) : '0.00'}';  
            }
          if (type == 'count' && displayValue != '-') {
            displayValue = '# $displayValue';
          }
          return _statItem(label, displayValue);
        }).toList(),
      ),
    ),
  );
}

Widget _statItem(String label, dynamic value) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        value?.toString() ?? '-',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,      // Much larger number!
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(
          fontSize: 16,      // Bigger label text!
          color: Colors.grey,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    ],
  );
}



@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text("Pending Deliveries"),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _fetchDeliveries(showSpinner: true),
        ),
          IconButton(
          icon: const Icon(Icons.logout),
          onPressed: _handleLogout,
          tooltip: 'Logout',
        ),
      ],
    ),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _fetchDeliveries(showSpinner: true),
        child: isLoading
            ? ListView(
                // Dummy list to allow pull-to-refresh while loading
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height - 200,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ],
              )
            : deliveries.isEmpty
                ? ListView(
                            children: [
                              SizedBox(
                                height: 540,
                                child: const Center(
                                  child: Text(
                                    'No deliveries assigned, go back to outlet.',
                                    style: TextStyle(fontSize: 18, color: Colors.grey),
                                  ),
                                ),
                              ),
                              _buildStatsBlock(),
                            ],
                          )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height - 100,
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: deliveries.length,
                          onPageChanged: (index) async {
                            setState(() {
                              currentPage = index;
                              etaText = null;
                              distanceText = null;
                              routePoints = [];
                            });
                            await _fetchW4AndRoute(index);
                          },
                          itemBuilder: (context, index) {
                            final delivery = deliveries[index];
                            if (delivery['latitude'] == null || delivery['longitude'] == null) {
                              return const Center(
                                child: Text('Delivery location not set', style: TextStyle(fontSize: 18, color: Colors.red)),
                              );
                            }
                            final coords = LatLng(delivery['latitude'], delivery['longitude']);
                            return Stack(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(formattedDate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                                          Text(formattedTime, style: const TextStyle(fontSize: 20)),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      Card(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        elevation: 3,
                                        child: Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text("Doc NO: ${delivery['external_order_id'] ?? 'N/A'} #${delivery['orderno']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                                                  Text(
                                                    "${index + 1}/${deliveries.length}",
                                                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                delivery['customer_name'] ?? '',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                              ),
                                              GestureDetector(
                                                onTap: () => _handleCall(delivery),
                                                child: Text(
                                                  delivery['customer_phone'] ?? '',
                                                  style: const TextStyle(color: Colors.blue, fontSize: 18),
                                                ),
                                              ),
                                              Text(
                                                delivery['delivery_address'] ?? '',
                                                style: const TextStyle(fontSize: 18),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(delivery['external_order_id'] ?? '', style: const TextStyle(fontSize: 18)),
                                                  GestureDetector(
                                                    onTap: () => _showItemsBreakdown(delivery),
                                                    child: Text(
                                                      "€${delivery['total_with_taxes'] ?? '0.00'}",
                                                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                              Text(
                                                    (delivery['is_paid'] == true) ? "PAID" : "UNPAID",
                                                    style: TextStyle(
                                                      color: (delivery['is_paid'] == true) ? Colors.green : Colors.red,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              if (etaText != null || distanceText != null)
                                                Container(
                                                  padding: const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    border: Border.all(color: Colors.black12),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      if (etaText != null)
                                                        Text("E.T.A $etaText", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                                      if (distanceText != null)
                                                        Text("Distance: $distanceText", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      if (driverLocation != null)
                                        SizedBox(
                                          height: 180,
                                          child: GestureDetector(
                                            onTap: _openMapScreen,
                                            child: AbsorbPointer(
                                              absorbing: true,
                                              child: GoogleMap(
                                                initialCameraPosition: CameraPosition(target: coords, zoom: 15), // higher zoom to focus on delivery
                                                onMapCreated: (controller) async {
                                                  _mapControllers[index] = controller;
                                                  // Center and zoom on the delivery pin directly
                                                  await Future.delayed(const Duration(milliseconds: 300));
                                                  controller.animateCamera(CameraUpdate.newLatLngZoom(coords, 15));
                                                },
                                                markers: {
                                                  Marker(markerId: const MarkerId("delivery"), position: coords),
                                                },
                                                myLocationEnabled: true,
                                                myLocationButtonEnabled: true,
                                              ),
                                            ),
                                          ),
                                        ),
                                _buildStatsBlock(),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  bottom: 16,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: ElevatedButton(
                                      onPressed: () => _handleDelivered(index),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text("DELIVERED", style: TextStyle(fontSize: 18)),
                                    ),
                                  ),
                                )
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
    ),
  );
}
void _handleLogout() async {
  final success = await Auth.AuthService.logout();
  if (success && mounted) {
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  } else {
    _showAlert('Logout Failed', 'Could not logout. Please try again.');
  }
}
void _handleDelivered(int index) async {
  final delivery = deliveries[index];
  final isPaid = delivery['is_paid'] == true;

  String? result = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Confirm Delivery'),
      actions: isPaid
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'ok'),
                child: const Text('OK'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'cash'),
                child: const Text('Cash'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'visa'),
                child: const Text('Visa'),
              ),
            ],
    ),
  );

  if (result == null) return; // Cancel pressed

  final prefs = await SharedPreferences.getInstance();
  final driverId = prefs.getInt('driver_id');
  final sessionId = prefs.getInt('session_id');
  final orderId = delivery['orderId'] as int?;
  final totalAmount = delivery['total_with_taxes'] is num
      ? delivery['total_with_taxes']
      : double.tryParse(delivery['total_with_taxes'] ?? '0') ?? 0.0;

  if (driverId == null || orderId == null || sessionId == null) {
    _showAlert('Error', 'Missing driver, session, or order ID.');
    return;
  }

  bool success = false;
  if (isPaid && result == 'ok') {
    // Already paid, just mark as delivered
    success = await DelServ.DeliveryService.markAsDelivered(driverId, orderId);
    final paymentSuccess = await DelServ.DeliveryService.completeOrder(
      orderId: orderId,
      paymentMethod: "",
      totalAmount: 0 ,
      driverId: driverId,
      sessionId: sessionId,
    );
    if (!success) {
      _showAlert('Warning', 'Payment was already processed, but could not mark as delivered.');
      return;
    }
    if (!paymentSuccess) {
      _showAlert('Failed', 'Payment could not be completed.');
      return;
    }
  } else if (!isPaid && (result == 'cash' || result == 'visa')) {
    // Complete order with payment, then mark as delivered
    final paymentSuccess = await DelServ.DeliveryService.completeOrder(
      orderId: orderId,
      paymentMethod: result,
      totalAmount: totalAmount,
      driverId: driverId,
      sessionId: sessionId,
    );
    if (!paymentSuccess) {
      _showAlert('Failed', 'Payment could not be completed.');
      return;
    }
    success = await DelServ.DeliveryService.markAsDelivered(driverId, orderId);
    if (!success) {
      _showAlert('Warning', 'Payment succeeded, but could not mark as delivered.');
      return;
    }
  }

  if (success) {
    await markOnDelivered(delivery);
    setState(() {
      deliveries.removeAt(index);
      loadedW4.remove(index);
      if (deliveries.isEmpty) {
        currentPage = 0;
      } else if (currentPage >= deliveries.length) {
        currentPage = deliveries.length - 1;
      }
    });

    if (deliveries.isNotEmpty) {
      await _fetchW4AndRoute(currentPage);
    }
      await _fetchDriverStats();
  } else {
    _showAlert('Failed', 'Could not update delivery.');
  }
}

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

 Future<void> markOnDelivered(Map<String, dynamic> delivery) async {
  final String? externalOrderId = delivery['external_order_id'];

  // Get the driver's current GPS
  Position pos = await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );
  
  // Log the GPS position
  print('[markOnDelivered] Driver GPS position: lat=${pos.latitude}, lng=${pos.longitude}, accuracy=${pos.accuracy}, timestamp=${pos.timestamp}');

  final double? latitude = pos.latitude;
  final double? longitude = pos.longitude;

  // Only proceed if all values exist
  if (externalOrderId != null && latitude != null && longitude != null) {
    print('[markOnDelivered] Upserting address for externalOrderId=$externalOrderId, lat=$latitude, lng=$longitude');
    final bool addressSaved = await DelServ.DeliveryService.upsertAddress(
      externalOrderId: externalOrderId,
      latitude: latitude,
      longitude: longitude,
    );
    if (addressSaved) {
      print('[markOnDelivered] Delivery address upserted successfully!');
    } else {
      print('[markOnDelivered] Failed to upsert delivery address.');
    }
  } else {
    print('[markOnDelivered] Cannot upsert address: missing values (externalOrderId=$externalOrderId, lat=$latitude, lng=$longitude)');
  }
}



  void _handleCall(Map<String, dynamic> delivery) async {
    final phone = delivery['customer_phone'] ?? '';
    final uri = Uri.parse('tel:$phone');

    if (phone.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: phone));
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        _showAlert("Call Failed", "We couldn't open your phone dialer. The number was copied so you can paste it manually.");
      }
    }
  }

  void _openMapScreen() {
    Navigator.pushNamed(context, '/map');
  }

  void _showItemsBreakdown(Map<String, dynamic> delivery) {
    final items = delivery['items'] ?? [];
    if (items.isEmpty) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Order Items'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: items.asMap().entries.map<Widget>((entry) {
            final idx = entry.key;
            final item = entry.value;
            return ListTile(
              leading: Text('${idx + 1}.', style: const TextStyle(fontWeight: FontWeight.bold)),
              title: Text(item['ArticleDesignation'] ?? ''),
              trailing: Text('€${item['TotalWithTaxes']?.toStringAsFixed(2) ?? '0.00'}'),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('Close')
          )
        ],
      ),
    );
  }
}
