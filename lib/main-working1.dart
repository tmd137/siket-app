import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final WebViewController controller;
  
  // --- CONFIGURATION ---
  final String remoteUrl = "http://192.168.1.5:8085/dashboard"; 
  final String apiUrl = "http://192.168.1.5:8085/api/exchangerates";
  final Duration apiSyncInterval = const Duration(minutes: 1);
  final Duration webReloadInterval = const Duration(minutes: 5);

  Timer? _apiSyncTimer;
  Timer? _webReloadTimer;
  Map<String, dynamic>? offlineData;
  String? _base64Logo;
  bool isUsingFallback = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _startServices();
  }

  void _initializeWebView() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              _switchToOfflineMode();
            }
          },
          onPageFinished: (url) {
            if (!url.startsWith('data:text/html')) {
              setState(() => isUsingFallback = false);
            }
          },
        ),
      );
    controller.loadRequest(Uri.parse(remoteUrl));
  }

  Future<void> _startServices() async {
    await _loadLocalLogo();
    await _fetchLatestRates();

    // Background Service 1: Sync Data
    _apiSyncTimer = Timer.periodic(apiSyncInterval, (_) => _fetchLatestRates());

    // Background Service 2: Reconnect to Live Site
    _webReloadTimer = Timer.periodic(webReloadInterval, (_) {
      if (isUsingFallback) {
        controller.loadRequest(Uri.parse(remoteUrl));
      }
    });
  }

  Future<void> _loadLocalLogo() async {
    try {
      final ByteData bytes = await rootBundle.load('assets/offline/logo.png');
      setState(() => _base64Logo = base64Encode(bytes.buffer.asUint8List()));
    } catch (e) {
      debugPrint("Asset Error: $e");
    }
  }

  Future<void> _fetchLatestRates() async {
    try {
      final response = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        setState(() => offlineData = json.decode(response.body));
        if (isUsingFallback) controller.loadHtmlString(_generateOfflineHtml());
      }
    } catch (e) {
      debugPrint("Background Sync: API Unreachable");
    }
  }

  void _switchToOfflineMode() {
    if (isUsingFallback) return;
    setState(() => isUsingFallback = true);
    controller.loadHtmlString(_generateOfflineHtml());
  }

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

  String _generateOfflineHtml() {
    final rates = offlineData?['rates'] as List<dynamic>? ?? [];
    final announcement = offlineData?['announcement'];
    final news = offlineData?['news'];
    final youtubeUrl = offlineData?['youtube'] as String? ?? "";
    final logoSrc = _base64Logo != null ? "data:image/png;base64,$_base64Logo" : "";

    // YouTube Embed Logic (Matching your Razor helper)
    String embedUrl = "";
    if (youtubeUrl.contains("v=")) {
      String videoId = youtubeUrl.split("v=").last.split("&").first;
      embedUrl = "https://www.youtube.com/embed/$videoId?autoplay=1&mute=1&loop=1&playlist=$videoId";
    }

    // Convert Rate objects to JS (Matching your Razor foreach)
    final jsRates = rates.map((r) => "{flag:'${_getFlag(r['currencyFlag'])}', currency:'${r['currency']}', cashBuy:'${r['cashBuying']}', cashSell:'${r['cashSelling']}', transBuy:'${r['transactionBuying']}', transSell:'${r['transactionSelling']}'}").join(',');

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
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
            border: 1vw solid #586e6c; position: relative; 
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
            font-size: 3.5vh; font-weight: bold; color: #586e6c; 
            white-space: nowrap; overflow: hidden; flex: 2; 
            border: 3px solid #abcf3b; padding: 5px; 
            margin-left: 1vw;
        }
        .marquee span { display: inline-block; padding-left: 100%; animation: marquee 30s linear infinite; }
        @keyframes marquee { 0% { transform: translateX(0); } 100% { transform: translateX(-100%); } }

        .main-grid {
            display: grid; grid-template-columns: 60% 40%;
            gap: 2vw; padding: 2vh 2vw; height: calc(100vh - 14vh);
        }

        .rates-section {
            background-color: #586e6c; color: #fff;
            padding: 1vh 1vw; box-shadow: 0 10px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }

        table { width: 100%; border-collapse: collapse; font-size: 2.8vh; }
        th { font-weight: bold; padding: 1.5vh 1vw; border-bottom: 2px solid rgba(255,255,255,0.2); }
        td { padding: 1.8vh 1vw; text-align: center; border-bottom: 1px solid rgba(255,255,255,0.1); }

        .flag-emoji { font-size: 5vh; }

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

                <!-- right col -->
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

  String _getFlag(String? countryCode) {
    if (countryCode == null || countryCode.length != 2) {
      return '🏦';
    }

    final code = countryCode.toUpperCase();

    // Special case: EU is not a country but has a flag
    if (code == 'EU') return '🇪🇺';

    // Convert ASCII letters to Regional Indicator Symbols
    return String.fromCharCodes(
      code.codeUnits.map((c) => 0x1F1E6 + c - 0x41),
    );
  }

  @override
  void dispose() {
    _apiSyncTimer?.cancel();
    _webReloadTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: WebViewWidget(controller: controller),
    );
  }
}