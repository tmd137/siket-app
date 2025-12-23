import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:kiosk_mode/kiosk_mode.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  //Start Kiosk Mode
  startKioskMode();

  // Android TV immersive mode
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const SiketTVApp());
}

class SiketTVApp extends StatelessWidget {
  const SiketTVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
      home: const SplashPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  InAppWebViewController? _controller;

  // ===== CONFIG =====
  final String remoteUrl = 'http://172.24.15.29:8085/dashboard';
  final String apiUrl = 'http://172.24.15.29:8085/api/exchangerates';

  final Duration apiSyncInterval = const Duration(minutes: 1);
  final Duration reconnectInterval = const Duration(minutes: 1);
  File? _cacheFile;
  bool _reconnecting = false;
  bool _showingOfflineHtml = false;

  Timer? _apiTimer;
  Timer? _reconnectTimer;

  bool _offlineMode = false;
  Map<String, dynamic>? _offlineData;
  String? _base64Logo;

  // ==================

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // Keeps the screen on indefinitely
    _init();
  }

  Future<void> _init() async {
    await _initCacheFile();        // 1️⃣ file system ready
    await _loadCachedRates();      // 2️⃣ preload cache
    await _loadLogo();

    await _loadInitialPage();

    _apiTimer = Timer.periodic(apiSyncInterval, (_) => _fetchRates());
    _reconnectTimer =
        Timer.periodic(reconnectInterval, (_) => _tryReconnect());
  }

  // ---------- FILE CACHE ----------
  Future<void> _initCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    _cacheFile = File('${dir.path}/rates_cache.json');
  }

  Future<void> _saveRatesToFile(String jsonStr) async {
    try {
       if (_cacheFile == null) return;
      await _cacheFile!.writeAsString(jsonStr, flush: true);
    } catch (_) {}
  }

  Future<void> _loadCachedRates() async {
    try {
      if (_cacheFile == null) return;

      if (await _cacheFile!.exists()) {
        final jsonStr = await _cacheFile!.readAsString();
        if (jsonStr.isNotEmpty) {
          _offlineData = json.decode(jsonStr);
          debugPrint('✅ Loaded cached rates');
        }
      }
    } catch (e) {
      debugPrint('❌ Cache read failed: $e');
    }
  }

  // ---------- NETWORK PROBE (CRITICAL) ----------
  Future<bool> _canReachServer() async {
    try {
      final res = await http
          .head(Uri.parse(remoteUrl))
          .timeout(const Duration(seconds: 5));
      return res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  // ---------- OFFLINE ----------
  void _switchToOffline() async {
    if (!mounted || _offlineMode) return;

    // Ensure cache is ready BEFORE switching
    if (_cacheFile == null) {
      await _initCacheFile();
    }

    _reconnecting = false;

    if (_offlineData == null) {
      await _loadCachedRates();
    }

    _showingOfflineHtml = true;

    setState(() => _offlineMode = true);
    await _controller?.loadData(data: _generateOfflineHtml(), mimeType: "text/html", encoding: "utf-8");
  }

  Future<void> _loadLogo() async {
    try {
      final bytes = await rootBundle.load('assets/offline/logo.png');
      _base64Logo = base64Encode(bytes.buffer.asUint8List());
    } catch (_) {
      _base64Logo = null;
    }
  }

  Future<void> _fetchRates() async {
     try {
      final res = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        _offlineData = json.decode(res.body);
        await _saveRatesToFile(res.body);

        if (_offlineMode && !_reconnecting) {
          await _controller?.loadData(data: _generateOfflineHtml(), mimeType: "text/html", encoding: "utf-8");
        }
      }
    } catch (_) {
      // API down → use cached JSON silently
      await _loadCachedRates();
      if (_offlineMode && !_reconnecting) {
        await _controller?.loadData(data: _generateOfflineHtml(), mimeType: "text/html", encoding: "utf-8");
      }
    }
  }

  // ---------- FLAG (ALL COUNTRIES) ----------
  String _getFlag(String? code) {
    if (code == null || code.length != 2) return '🏦';

    final cc = code.toUpperCase();
    if (cc == 'EU') return '🇪🇺';

    return String.fromCharCodes(cc.codeUnits.map((c) => 0x1F1E6 + c - 0x41));
  }

  // ---------- OFFLINE HTML ----------
  String _generateOfflineHtml(){   
    final rates = _offlineData?['rates'] as List<dynamic>? ?? [];
    final announcement = _offlineData?['announcement'];
    final news = _offlineData?['news'];
    final youtubeUrl = _offlineData?['youtube'] as String? ?? '';

    final logoSrc = _base64Logo != null
        ? 'data:image/png;base64,$_base64Logo'
        : '';

    final jsRates = rates
        .map(
          (r) =>
              "{flag:'${_getFlag(r['currencyFlag'])}',currency:'${r['currency']}',cashBuy:'${r['cashBuying']}',cashSell:'${r['cashSelling']}',transBuy:'${r['transactionBuying']}',transSell:'${r['transactionSelling']}'}",
        )
        .join(',');

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; border-radius: 0 !important; scrollbar-width: none; }
        *::-webkit-scrollbar { display: none; }

        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
            color: #333; height: 100vh; overflow: hidden;
        }

        .tv-frame { width: 100vw; height: 100vh; }
        .frame-inner { 
            width: 100%; height: 100%; overflow: hidden; 
            border: 0.5vw solid #586e6c; position: relative; 
            display: grid; grid-template-rows: auto 1fr;
        }

        header {
            background: rgba(255, 255, 255, 0.95); backdrop-filter: blur(15px);
            padding: 1vh 2vw; display: flex; align-items: center;
            justify-content: space-between; box-shadow: 0 6px 30px rgba(0,0,0,0.15);
            height: 12vh; gap: 3vw;
        }

        .logo-section img { height: 11vh; max-height: 120px; }

        .datetime { text-align: center; color: #333; }
        .date { font-size: 2.5vh; font-weight: 900; letter-spacing: 1px; }
        .time { font-size: 3.5vh; font-weight: 900; color: #586e6c; letter-spacing: 2px; }

        .marquee { 
            font-size: 3vh; font-weight: bold; color: #586e6c; 
            white-space: nowrap; overflow: hidden; flex: 2; 
            border: 3px solid #abcf3b; padding: 5px; 
            margin-left: 6vw; padding: 2vh;
        }
        .marquee span { display: inline-block; padding-left: 100%; animation: marquee 30s linear infinite; }
        @keyframes marquee { 0% { transform: translateX(0); } 100% { transform: translateX(-100%); } }

        .main-grid {
            display: grid; grid-template-columns: 3fr 2fr; max-width: 1920px;   /* Prevents extreme stretching on large TVs */
            gap: 2vw; padding: 2vh 2vw; height: calc(100vh - 14vh);
        }

        .rates-section {
            background-color: #586e6c; color: #fff;
            padding: 1vh 1vw; box-shadow: 0 10px 40px rgba(0,0,0,0.1);
            overflow: hidden; width: 100% !important;
        }

        table { width: 100%; border-collapse: collapse; font-size: 2.8vh; }
        th { font-weight: bold; padding: 1.5vh 1vw; border-bottom: 2px solid rgba(255,255,255,0.2); }
        td { padding: 1.8vh 1vw; text-align: center; border-bottom: 1px solid rgba(255,255,255,0.1); }

        .flag-emoji { font-size: 7vh; }

        .flag-img {
            width: 8vh;
            height: 6vh;
            border-radius: 50%;
            box-shadow: 0 4px 12px rgba(0,0,0,0.2);
        }

        .right-column { display: flex; flex-direction: column; gap: 2vh; height: 100%; }
        
        .news-section {
            background: rgba(255, 255, 255, 0.9); padding: 2vh 1.5vw;
            flex: 0 0 30%; display: flex; flex-direction: column; overflow: hidden;
        }
        .news-section h2 { font-size: 4vh; color: #586e6c; margin-bottom: 1vh; text-align: center; }
        .news-content { font-size: 2.8vh; line-height: 1.3; color: #333; overflow-y: auto; }

        .youtube-section { flex: 0 0 67%; display: flex; flex-direction: column; }
        .video-wrapper { 
            position: relative; width: 100%; flex: 1; 
            background: #000; box-shadow: 0 8px 30px rgba(0,0,0,0.2); 
        }
        .video-wrapper iframe { position: absolute; width: 100%; height: 100%; border: none; }
        
        .no-content { text-align: center; color: #777; font-size: 3.5vh; font-style: italic; margin: auto; }
    </style>
</head>
<body>
    <div class="tv-frame">
        <div class="frame-inner">
            <header>
                <div class="logo-section">
                    ${logoSrc.isNotEmpty 
                      ? '<img src="$logoSrc" alt="Logo" />'
                      : '<strong>SIKET BANK</strong>'}
                </div>
                <div class="datetime">
                    <div class="date" id="liveDate">Loading...</div>
                    <div class="time" id="liveTime">00:00:00</div>
                </div>
                <div class="marquee">
                    <span>
                        <strong>${announcement?['title'] ?? 'SIKET BANK'}:</strong> 
                        ${announcement?['content'] ?? 'Welcome to Siket Bank Exchange Rate Dashboard'}
                    </span>
                </div>
            </header>

            <div class="main-grid">
                <section class="rates-section">
                    <table id="ratesTable">
                        <thead>
                            <tr>
                                <th rowspan="2" colspan="2">Currency</th>
                                <th colspan="2">Cash</th>
                                <th colspan="2">Transaction</th>
                            </tr>
                            <tr style="font-size: 2vh;">
                                <th>Buying</th><th>Selling</th>
                                <th>Buying</th><th>Selling</th>
                            </tr>
                        </thead>
                        <tbody></tbody>
                    </table>
                </section>
            <!-- News & YouTube Column -->
            </div>
        </div>
    </div>

    <script>
        function updateTime() {
            const now = new Date();
            document.getElementById('liveTime').textContent = now.toLocaleTimeString('en-GB');
            document.getElementById('liveDate').textContent = now.toLocaleDateString('en-GB', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
        }
        setInterval(updateTime, 1000);
        updateTime();

        const allRates = [$jsRates];
        const fixedRates = allRates.slice(0, 3);
        const rotatingRates = allRates.slice(3);
        const tbody = document.querySelector('#ratesTable tbody');
        let currentIndex = 0;

        function displayRates() {
            tbody.innerHTML = '';
            // 1. Show Fixed
            fixedRates.forEach(r => addRow(r));
            
            // 2. Show Rotating
            if (rotatingRates.length > 0) {
                const start = currentIndex * 3;
                let chunk = rotatingRates.slice(start, start + 3);
                while (chunk.length < 3 && rotatingRates.length > 0) {
                    chunk = chunk.concat(rotatingRates.slice(0, 3 - chunk.length));
                }
                chunk.forEach(r => addRow(r));
            }
        }

        function addRow(rate) {
            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="flag-emoji">\${rate.flag}</span></td>
                <td style="text-align:left"><strong>\${rate.currency}</strong></td>
                <td>\${rate.cashBuy}</td><td>\${rate.cashSell}</td>
                <td>\${rate.transBuy}</td><td>\${rate.transSell}</td>
            `;
            tbody.appendChild(tr);
        }

        if (rotatingRates.length > 0) {
            setInterval(() => {
                currentIndex = (currentIndex + 1) % Math.ceil(rotatingRates.length / 3);
                displayRates();
            }, 10000);
        }
        displayRates();
    </script>
</body>
</html>
''';
  }

  @override
  void dispose() {
    _apiTimer?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialPage() async {
    if (await _canReachServer()) {
        _showingOfflineHtml = false;
      await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(remoteUrl)));
    } else {
      _switchToOffline();
    }
  }

  void _tryReconnect() async {
    if (!_offlineMode || _reconnecting) return;

    setState(() => _reconnecting = true);

    if (await _canReachServer()) {
      _showingOfflineHtml = false;
      await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(remoteUrl)));
      // Success case handled in onLoadStop
    } else {
      // Server still down → refresh offline page with latest cache
      _reconnecting = false;
      if (_offlineData != null) {
        _showingOfflineHtml = true;
        await _controller?.loadData(data: _generateOfflineHtml(), mimeType: "text/html", encoding: "utf-8");
      }
      // If no cache, stay on current (old) offline page
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: InAppWebView(
        initialSettings: InAppWebViewSettings(
          // This is the equivalent of .setJavaScriptMode(JavaScriptMode.unrestricted)
          javaScriptEnabled: true, 
          
          // This is the equivalent of .setMediaPlaybackRequiresUserGesture(false)
          // It allows your video to autoplay without the user clicking "Play"
          mediaPlaybackRequiresUserGesture: false,
          
          // Recommended for TV Dashboards
          allowsInlineMediaPlayback: true,
          transparentBackground: true,
          useWideViewPort: true,
          loadWithOverviewMode: true,
          builtInZoomControls: false,
          displayZoomControls: false,

          //High-priority settings for local video/TV
          mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          
          // Performance and UI
          preferredContentMode: UserPreferredContentMode.DESKTOP,
          safeBrowsingEnabled: false,
          // This allows you to connect your laptop's Chrome to the TV
          isInspectable: true,

        ),
        onWebViewCreated: (InAppWebViewController controller) {
          _controller = controller;
        },
        onLoadError: (controller, url, code, message) async {
          if (_reconnecting) return;
          if (code != -999) {  // Ignore canceled requests
            setState(() => _reconnecting = false);
            _switchToOffline();
          }
        },
        onLoadStop: (controller, url) async {
          if (_showingOfflineHtml) return;

          if (url != null && url.toString().startsWith('http') && url.toString().contains('172.24.15.29')) {
            setState(() {
              _offlineMode = false;
              _reconnecting = false;
            });

            // Force play via JS after page loads
            // We wrap it in a small timeout to ensure the DOM is fully ready
            await controller.evaluateJavascript(source: """
              setTimeout(function() {
                var videos = document.querySelectorAll('video');
                videos.forEach(function(v) {
                  v.muted = true; // Essential for autoplay
                  v.play().catch(function(error) {
                    console.log("Autoplay blocked: ", error);
                  });
                });
              }, 1000);
            """);

          } else if (_reconnecting) {
            if (!(await _canReachServer())) {
              _switchToOffline();
            }
          }
        },
      ),
    );
  }
}

/// Splash Page
/// 
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/offline/logo.png',
              width: 220,
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              strokeWidth: 4,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}