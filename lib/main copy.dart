import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TVApp());
}

class TVApp extends StatelessWidget {
  const TVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewPage(),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController controller;

  final String url = "http://172.24.15.29:8085";// "http://192.168.1.4:8085"; 
  final int autoReloadMinutes = 3;

  Timer? _timer;

  @override
  void initState() {
    super.initState();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => debugPrint('Loading $url'),
          onPageFinished: (_) => debugPrint('Loaded $url'),
          onWebResourceError: (error) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 20),
                content: Text(
                  'ERROR ${error.errorCode}\n${error.description}\nURL: $url',
                  style: const TextStyle(fontSize: 28),
                ),
              ),
            );
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    // Fixed: Timer callback now receives the Timer parameter
    _timer = Timer.periodic(Duration(minutes: autoReloadMinutes), (timer) {
      controller.reload();
      debugPrint('Auto-reload at ${DateTime.now()}');
    });
  }

  void _reload() {
    controller.reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Page reloaded', style: TextStyle(fontSize: 32)),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 1),
      ),
    );
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      _reload();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: _onKey,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _reload();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              WebViewWidget(controller: controller),

              // Debug overlay (only visible in debug builds)
              if (kDebugMode)
                Positioned(
                  top: 30,
                  left: 30,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.black54,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('URL: $url',
                            style: const TextStyle(color: Colors.white, fontSize: 18)),
                        const Text('Any remote button → reload',
                            style: TextStyle(color: Colors.white70, fontSize: 16)),
                        Text('Auto-reload every $autoReloadMinutes min',
                            style: const TextStyle(color: Colors.white70, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    super.dispose();
  }
}