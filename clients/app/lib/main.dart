import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cupertino_ui/cupertino_ui.dart';

import 'application/vpn_controller.dart';
import 'infrastructure/native_vpn.dart';
import 'presentation/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(DuctTapeApp(controller: VpnController(NativeVpn())));
}

class DuctTapeApp extends StatefulWidget {
  const DuctTapeApp({super.key, required this.controller});
  final VpnController controller;
  @override
  State<DuctTapeApp> createState() => _DuctTapeAppState();
}

class _DuctTapeAppState extends State<DuctTapeApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.start();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final blue = dark ? const Color(0xff2997ff) : const Color(0xff0066cc);
    final family =
        defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS
        ? '.SF Pro Text'
        : 'Segoe UI';
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: dark ? Colors.black : const Color(0xfff5f5f7),
      fontFamily: family,
      fontFamilyFallback: const ['Segoe UI', 'Arial'],
      colorScheme: ColorScheme.fromSeed(seedColor: blue, brightness: brightness)
          .copyWith(
            primary: blue,
            onPrimary: dark ? Colors.black : Colors.white,
            surface: dark ? const Color(0xff1c1c1e) : Colors.white,
          ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: blue,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.7,
        ),
        bodyMedium: TextStyle(fontSize: 17, height: 1.47),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(120, 48),
          textStyle: TextStyle(
            fontFamily: family,
            fontFamilyFallback: const ['Segoe UI', 'Arial'],
            fontSize: 17,
            fontWeight: FontWeight.w400,
          ),
          shape: const StadiumBorder(),
          backgroundColor: blue,
          foregroundColor: dark ? Colors.black : Colors.white,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: blue,
          textStyle: TextStyle(
            fontFamily: family,
            fontFamilyFallback: const ['Segoe UI', 'Arial'],
            fontSize: 17,
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
      ),
      appBarTheme: AppBarTheme(
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Duct-Tape VPN',
    debugShowCheckedModeBanner: false,
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: child!,
    ),
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    home: Home(controller: widget.controller),
  );
}
