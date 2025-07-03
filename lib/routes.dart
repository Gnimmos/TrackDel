import 'package:flutter/material.dart';
import 'package:trackdel/screens/login_screen.dart';
import 'package:trackdel/screens/map_screen.dart';
import 'package:trackdel/screens/pending_deliveries_screen.dart';


final Map<String, WidgetBuilder> appRoutes = {
  '/login': (context) => const LoginScreen(),
  '/map': (context) => const MapScreen(),
  '/pending': (context) => const PendingDeliveriesScreen(),
};
