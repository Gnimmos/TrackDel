import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const TrackDelApp());
}

class TrackDelApp extends StatelessWidget {
  const TrackDelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'TrackDel',
        theme: ThemeData(primarySwatch: Colors.blue),
        initialRoute: '/login',
        routes: appRoutes,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
