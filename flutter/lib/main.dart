import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/device_list_screen.dart';
import 'screens/login_screen.dart';
import 'state/app_state.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const OpenTagViewerApp(),
    ),
  );
}

class OpenTagViewerApp extends StatelessWidget {
  const OpenTagViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenTagViewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: const _AppEntryPoint(),
    );
  }
}

/// Decides whether to show the login screen or the device list based on
/// whether a stored Apple account session exists.
class _AppEntryPoint extends StatefulWidget {
  const _AppEntryPoint();

  @override
  State<_AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends State<_AppEntryPoint> {
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await context.read<AppState>().init();
    if (mounted) setState(() => _initialised = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialised) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isLoggedIn = context.watch<AppState>().isLoggedIn;
    return isLoggedIn ? const DeviceListScreen() : const LoginScreen();
  }
}
