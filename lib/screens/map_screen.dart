import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackdel/services/location_service.dart' as LocService;
import 'package:trackdel/services/delivery_service.dart' as DelServ;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  LatLng? driverLocation;
  List<Map<String, dynamic>> deliveries = [];
  List<LatLng> routePoints = [];
  bool isLoading = true;
  BitmapDescriptor? _motorcycleIcon;
  GoogleMapController? _mapController;
  int activeOrderIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadMotorcycleIcon();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchDeliveriesAndRoute());
  }

  Future<void> _loadMotorcycleIcon() async {
    final icon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(6, 6)),
      'assets/motorcycle.png',
    );
    setState(() {
      _motorcycleIcon = icon;
    });
  }

  Future<void> _launchNavigation(double lat, double lng) async {
    final url = 'google.navigation:q=$lat,$lng&mode=d';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch navigation.')),
      );
    }
  }

  Future<void> _fetchDeliveriesAndRoute() async {
    setState(() => isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final driverId = prefs.getInt('driver_id');
    if (driverId == null) {
      setState(() => isLoading = false);
      return;
    }

    deliveries = await DelServ.DeliveryService.fetchActiveDeliveries(driverId);
    if (deliveries.isEmpty) {
      setState(() => isLoading = false);
      return;
    }

    // Get driver location
    final pos = await LocService.LocationService.getLiveLocation();
    if (pos != null) driverLocation = LatLng(pos.latitude, pos.longitude);

    // For the first order (active), fetch route as in pending screen
    if (driverLocation != null && deliveries[activeOrderIndex]['latitude'] != null && deliveries[activeOrderIndex]['longitude'] != null) {
      final destination = LatLng(deliveries[activeOrderIndex]['latitude'], deliveries[activeOrderIndex]['longitude']);
      final route = await DelServ.DeliveryService.getRouteInfo(origin: driverLocation!, destination: destination);
      if (route != null && route['steps'] != null) {
        setState(() {
          routePoints = extractRouteFromSteps(route['steps']);
        });
      }
    }

    setState(() => isLoading = false);

    // Fit map to all markers
    if (_mapController != null && driverLocation != null && deliveries.isNotEmpty) {
      _fitMapToMarkers();
    }
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

  void _fitMapToMarkers() async {
    List<LatLng> points = [
      if (driverLocation != null) driverLocation!,
      ...deliveries.where((d) => d['latitude'] != null && d['longitude'] != null)
          .map((d) => LatLng(d['latitude'], d['longitude']))
    ];
    double minLat = points.map((p) => p.latitude).reduce(min);
    double maxLat = points.map((p) => p.latitude).reduce(max);
    double minLng = points.map((p) => p.longitude).reduce(min);
    double maxLng = points.map((p) => p.longitude).reduce(max);

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    await Future.delayed(const Duration(milliseconds: 400));
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || _motorcycleIcon == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (deliveries.isEmpty || driverLocation == null) {
      return const Scaffold(
        body: Center(child: Text('No deliveries or location found', style: TextStyle(fontSize: 18, color: Colors.grey))),
      );
    }

    final markers = <Marker>{
      // Driver marker with motorcycle icon
      Marker(
        markerId: const MarkerId("driver"),
        position: driverLocation!,
        icon: _motorcycleIcon!,
        infoWindow: const InfoWindow(title: 'You'),
      ),
      // Delivery pins
      ...deliveries.asMap().entries.map((entry) {
        final i = entry.key;
        final delivery = entry.value;
        if (delivery['latitude'] == null || delivery['longitude'] == null) return null;
        return Marker(
          markerId: MarkerId("delivery_$i"),
          position: LatLng(delivery['latitude'], delivery['longitude']),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              i == activeOrderIndex ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(title: "Order #${i + 1}"),
        );
      }).whereType<Marker>(),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Map & Deliveries')),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: driverLocation!, zoom: 14),
        markers: markers,
        polylines: routePoints.isNotEmpty
            ? {
                Polyline(
                  polylineId: const PolylineId('route'),
                  color: Colors.blue,
                  width: 6,
                  points: routePoints,
                )
              }
            : {},
        onMapCreated: (controller) {
          _mapController = controller;
          // Animate camera to fit markers
          _fitMapToMarkers();
        },
        myLocationEnabled: true,
        zoomControlsEnabled: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: Icon(Icons.navigation),
        label: Text('Navigate'),
        onPressed: () {
          final delivery = deliveries[activeOrderIndex];
          final lat = delivery['latitude'];
          final lng = delivery['longitude'];
          if (lat != null && lng != null) {
            _launchNavigation(lat, lng);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Delivery location not found.')),
            );
          }
        },
      ),
    );
  }
}
