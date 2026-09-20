import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const YtDownloaderApp());
}

class YtDownloaderApp extends StatelessWidget {
  const YtDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MP3 Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          surface:    Color(0xFF0F0F14),
          surfaceContainerHighest: Color(0xFF1C1C24),
          primary:    Color(0xFF7C6FF7),   // 부드러운 퍼플
          secondary:  Color(0xFF4ECDC4),   // 틸
          onSurface:  Color(0xFFE8E8F0),
          onPrimary:  Color(0xFFFFFFFF),
          error:      Color(0xFFFF6B6B),
        ),
        fontFamily: 'sans-serif',
        scaffoldBackgroundColor: const Color(0xFF0F0F14),
      ),
      home: const HomeScreen(),
    );
  }
}
