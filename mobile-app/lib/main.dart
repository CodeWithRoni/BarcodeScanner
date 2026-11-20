import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/services/app_controller.dart';
import 'src/ui/home_screen.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
  );
  final app = await AppController.bootstrap();
  runApp(BarcodeSyncApp(app: app));
}

class BarcodeSyncApp extends StatelessWidget {
  const BarcodeSyncApp({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BarcodeSync',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: HomeScreen(app: app),
    );
  }
}
