import 'package:flutter/material.dart';
import 'package:ermis/screens/login_screen.dart';
import 'package:ermis/screens/map_screen.dart';
import 'package:ermis/screens/pending_deliveries_screen.dart';


final Map<String, WidgetBuilder> appRoutes = {
  '/login': (context) => const LoginScreen(),
  '/map': (context) => const MapScreen(),
  '/pending': (context) => const PendingDeliveriesScreen(),
};
