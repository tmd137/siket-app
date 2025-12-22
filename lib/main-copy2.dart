import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: TVDashboard(),
  ));
}

class TVDashboard extends StatefulWidget {
  const TVDashboard({super.key});
  @override
  State<TVDashboard> createState() => _TVDashboardState();
}

class _TVDashboardState extends State<TVDashboard> {
  InAppWebViewController? _webViewController;
  bool _isOffline = false;
  Timer? _retryTimer;

  final String primaryUrl = "http://192.168.1.8:8085/TVDashboard"; // Your local URL
  final String apiUrl = "http://192.168.1.8:8085/api/exchangerates"; // ← CHANGE TO YOUR JSON API URL
  final Duration retryInterval = const Duration(seconds: 30);

  late final String _jsonFilePath;

  @override
  void initState() {
    super.initState();
    _initPaths();
    _fetchAndSaveJson(); // Initial fetch
    _startRetryTimer();
  }

  Future<void> _initPaths() async {
    final dir = await getApplicationDocumentsDirectory();
    _jsonFilePath = '${dir.path}/exchange_rates.json';
  }

  // Fetch JSON from API and save locally
  Future<void> _fetchAndSaveJson() async {
    try {
      final response = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final file = File(_jsonFilePath);
        await file.writeAsString(response.body);
        debugPrint('JSON saved successfully');
      }
    } catch (e) {
      debugPrint('Failed to fetch JSON: $e');
    }
  }

  Future<String?> _loadSavedJson() async {
    try {
      final file = File(_jsonFilePath);
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      debugPrint('Failed to read saved JSON: $e');
    }
    return null;
  }

  void _loadPrimaryUrl() {
    _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(primaryUrl)));
  }

  Future<void> _loadOfflinePage() async {
    _webViewController?.loadFile(assetFilePath: "assets/offline/index.html");

    // Wait a bit for page to load, then inject JSON
    Timer(const Duration(milliseconds: 800), () async {
      final jsonString = await _loadSavedJson();
      final escapedJson = jsonEscape(jsonString ?? '{}');
      await _webViewController?.evaluateJavascript(
        source: "displayRates($escapedJson);",
      );
    });
  }

  // Helper to escape JSON for JS
  String jsonEscape(String json) {
    return json.replaceAll("'", "\\'").replaceAll('"', '\\"');
  }

  void _startRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(retryInterval, (_) {
      _fetchAndSaveJson(); // Always try to update JSON
      if (_isOffline) {
        _loadPrimaryUrl();
      }
    });
  }

  void _manualReload() {
    _fetchAndSaveJson();
    if (_isOffline) {
      _loadPrimaryUrl();
    } else {
      _webViewController?.reload();
    }
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      _manualReload();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(primaryUrl)),
              initialOptions: InAppWebViewGroupOptions(
                crossPlatform: InAppWebViewOptions(javaScriptEnabled: true),
                android: AndroidInAppWebViewOptions(useHybridComposition: true),
              ),
              onWebViewCreated: (controller) => _webViewController = controller,
              onLoadStart: (_, _) => setState(() => _isOffline = false),
              onLoadStop: (_, _) async {
                setState(() => _isOffline = false);
                await _fetchAndSaveJson(); // Update JSON on successful load
              },
              onLoadError: (_, _, code, message) {
                setState(() => _isOffline = true);
                _loadOfflinePage();
              },
              onLoadHttpError: (_, _, code, message) {
                setState(() => _isOffline = true);
                _loadOfflinePage();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }
}