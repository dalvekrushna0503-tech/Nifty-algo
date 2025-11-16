/* Nifty Intraday Algo Android App (Flutter) - Dark Theme File: main.dart

--- WHAT THIS PROJECT DOES ---

5-minute intraday algo for NIFTY futures (MIS / Intraday)

All strategy logic runs inside the app (no TradingView)

Uses Angel One SmartAPI REST endpoints to fetch candle/quote data and place orders

9-EMA / 20-EMA crossover + big candle + wick + volume rules implemented

ON/OFF switch, logs, minimal settings screen


--- IMPORTANT / SECURITY ---

Fill your ANGEL_CLIENT_ID, ANGEL_API_KEY, ANGEL_PASSWORD in the app (or better: store securely)

For production, do NOT hardcode credentials. Use Android Keystore or secure backend token service.

Angel One SmartAPI endpoints used via REST. This code shows how to call them; adapt as per your SmartAPI app details.


--- HOW TO BUILD ---

1. Install Flutter SDK and Android toolchain.


2. Create a new Flutter project and replace lib/main.dart with this file.


3. Add dependencies in pubspec.yaml: http, provider dependencies: flutter: sdk: flutter http: ^0.13.6 provider: ^6.0.5


4. flutter pub get


5. flutter run -d emulator-5554  (or build an APK)



--- CONFIGURATION ---

Set the CLIENT_ID, API_KEY, PASSWORD in the UI login screen when first running the app.

For testing, use a demo account or paper-trading environment if available.


--- LIMITATIONS ---

This is sample code for educational use. Test thoroughly on a paper account before using real funds.

Angel One's exact REST contract, tokens, or symbol-tokens may change; adapt endpoints accordingly.


*/

import 'dart:async'; import 'dart:convert';

import 'package:flutter/material.dart'; import 'package:http/http.dart' as http; import 'package:provider/provider.dart';

// ----------------------------- // CONFIG / CONSTANTS // ----------------------------- const String ANGEL_BASE = 'https://apiconnect.angelbroking.com'; // NOTE: The above may change; confirm SmartAPI base URL from Angel documentation.

// ----------------------------- // MODELS // ----------------------------- class Candle { final DateTime time; final double open, high, low, close; final double volume;

Candle({required this.time, required this.open, required this.high, required this.low, required this.close, required this.volume});

factory Candle.fromList(List<dynamic> arr) { // adapt based on the API response array order return Candle( time: DateTime.fromMillisecondsSinceEpoch((arr[0] as int)), open: (arr[1] as num).toDouble(), high: (arr[2] as num).toDouble(), low: (arr[3] as num).toDouble(), close: (arr[4] as num).toDouble(), volume: ((arr.length > 5) ? (arr[5] as num).toDouble() : 0.0), ); } }

// ----------------------------- // ANGEL API SERVICE // ----------------------------- class AngelApiService { String apiKey = ''; String clientId = ''; String password = ''; String jwtToken = ''; // session token

Future<bool> generateSession() async { // SmartAPI session generation (example; adapt to exact endpoint params) final url = Uri.parse('$ANGEL_BASE/rest/auth/angelbroking/user/v1/loginByPassword'); // This is illustrative — please replace with proper SmartAPI session endpoint final body = jsonEncode({ 'clientcode': clientId, 'password': password, 'apiKey': apiKey, });

final resp = await http.post(url, headers: {'Content-Type': 'application/json'}, body: body);
if (resp.statusCode == 200) {
  final map = jsonDecode(resp.body);
  if (map['status'] == 'SUCCESS' && map.containsKey('data')) {
    jwtToken = map['data']['jwtToken'] ?? '';
    return true;
  }
}
return false;

}

Future<List<Candle>> fetchCandleData(String symbolToken, String interval, int fromTsMs, int toTsMs) async { // Example: GET candles API — adapt to correct URL/params final url = Uri.parse('$ANGEL_BASE/rest/secure/marketdata/v1/getCandleData?symbolToken=$symbolToken&interval=$interval&from=$fromTsMs&to=$toTsMs'); final resp = await http.get(url, headers: { 'Authorization': 'Bearer $jwtToken', 'x-api-key': apiKey, 'Content-Type': 'application/json' }); if (resp.statusCode == 200) { final map = jsonDecode(resp.body); // Assume map['data'] is a list of arrays final data = map['data'] as List<dynamic>; return data.map((e) => Candle.fromList(e as List<dynamic>)).toList(); } throw Exception('Failed to fetch candles: ${resp.statusCode}'); }

Future<String> placeOrder(Map<String, dynamic> params) async { final url = Uri.parse('$ANGEL_BASE/rest/secure/market/v1/placeOrder'); final resp = await http.post(url, headers: { 'Authorization': 'Bearer $jwtToken', 'x-api-key': apiKey, 'Content-Type': 'application/json' }, body: jsonEncode(params));

if (resp.statusCode == 200) {
  final map = jsonDecode(resp.body);
  if (map['status'] == 'SUCCESS') {
    return map['data']['orderId'].toString();
  } else {
    return 'ERROR: ${map['message'] ?? resp.body}';
  }
}
return 'HTTP_ERROR: ${resp.statusCode}';

} }

// ----------------------------- // STRATEGY ENGINE (9 EMA / 20 EMA + candle rules) // ----------------------------- class StrategyEngine { // Compute EMA for list of closing prices static List<double> ema(List<double> prices, int period) { if (prices.isEmpty) return []; List<double> out = List.filled(prices.length, 0.0); double k = 2.0 / (period + 1); out[0] = prices[0]; for (int i = 1; i < prices.length; i++) { out[i] = prices[i] * k + out[i - 1] * (1 - k); } return out; }

// Evaluate last candle for signal static Map<String, dynamic> evaluate(List<Candle> candles) { // We expect candles in chronological order if (candles.length < 30) return {'signal': 'NONE'};

List<double> closes = candles.map((c) => c.close).toList();
List<double> volumes = candles.map((c) => c.volume).toList();

List<double> ema9 = ema(closes, 9);
List<double> ema20 = ema(closes, 20);

int last = candles.length - 1;
Candle L = candles[last];
double lastEma9 = ema9[last];
double lastEma20 = ema20[last];

// Candle size and wick check
double body = (L.close - L.open).abs();
double upperWick = L.high - (L.close > L.open ? L.close : L.open);
double lowerWick = (L.close > L.open ? L.open : L.close) - L.low;
double wick = upperWick + lowerWick;

double avgVol = volumes.sublist((volumes.length - 20)).reduce((a, b) => a + b) / 20.0;

bool isGreen = L.close > L.open;

// Big candle threshold: body > average body of last N
List<double> bodies = candles.map((c) => (c.close - c.open).abs()).toList();
double avgBody = bodies.sublist(bodies.length - 20).reduce((a, b) => a + b) / 20.0;

bool bigCandle = body >= avgBody * 1.2; // 20% bigger than avg body
bool goodVolume = L.volume >= avgVol * 1.1;
bool smallWick = wick <= body * 0.4; // wick less than 40% of body
bool noWick = wick <= body * 0.05; // near-zero wick

// Buy rules
if (isGreen && (L.close >= lastEma9 || L.close >= lastEma20) && (bigCandle) && (goodVolume) && (smallWick)) {
  int strength = noWick ? 100 : 50;
  String reason = 'Green big candle close above EMA, vol ok, wick ok';
  if (ema9[last] > ema20[last]) reason += ' + EMA crossover up';
  return {'signal': 'BUY', 'strength': strength, 'reason': reason, 'price': L.close};
}

// Sell rules
if (!isGreen && (L.close <= lastEma9 || L.close <= lastEma20) && (bigCandle) && (goodVolume) && (smallWick)) {
  int strength = noWick ? 100 : 50;
  String reason = 'Red big candle close below EMA, vol ok, wick ok';
  if (ema9[last] < ema20[last]) reason += ' + EMA crossover down';
  return {'signal': 'SELL', 'strength': strength, 'reason': reason, 'price': L.close};
}

return {'signal': 'NONE'};

} }

// ----------------------------- // PROVIDER: App State // ----------------------------- class AppState extends ChangeNotifier { final AngelApiService api = AngelApiService(); bool running = false; String logs = ''; Timer? _timer; String symbolTokenNifty = '256265'; // placeholder symbol token for NIFTY (example) String interval = '5minute'; int qty = 25; // default quantity — adjust for lot size String product = 'MIS';

void appendLog(String s) { final ts = DateTime.now().toIso8601String(); logs = '$ts  -  $s\n' + logs; notifyListeners(); }

Future<bool> login(String clientId, String apiKey, String password) async { api.clientId = clientId; api.apiKey = apiKey; api.password = password;

appendLog('Attempting login...');
bool ok = await api.generateSession();
appendLog(ok ? 'Login success' : 'Login failed');
return ok;

}

void startAlgo() { if (running) return; running = true; appendLog('Algo started'); timer = Timer.periodic(Duration(seconds: 15), () => runOnce()); notifyListeners(); }

void stopAlgo() { running = false; _timer?.cancel(); appendLog('Algo stopped'); notifyListeners(); }

Future<void> runOnce() async { try { // fetch last 60 candles (5-minute timeframe -> 56060 ms window?) final toTs = DateTime.now().millisecondsSinceEpoch; final fromTs = DateTime.now().subtract(Duration(minutes: 5 * 60)).millisecondsSinceEpoch; appendLog('Fetching candles...'); List<Candle> candles = await api.fetchCandleData(symbolTokenNifty, '5minute', fromTs, toTs); appendLog('Fetched ${candles.length} candles'); final result = StrategyEngine.evaluate(candles); appendLog('Strategy result: ${result['signal']} ${result.containsKey('reason') ? result['reason'] : ''}');

if (result['signal'] == 'BUY') {
    // Place a market BUY order
    Map<String, dynamic> order = {
      'variety': 'NORMAL',
      'tradingsymbol': 'NIFTY',
      'symboltoken': symbolTokenNifty,
      'transactiontype': 'BUY',
      'exchange': 'NFO',
      'ordertype': 'MARKET',
      'producttype': product,
      'duration': 'DAY',
      'quantity': qty
    };
    appendLog('Placing BUY order...');
    String res = await api.placeOrder(order);
    appendLog('Order response: $res');
  } else if (result['signal'] == 'SELL') {
    Map<String, dynamic> order = {
      'variety': 'NORMAL',
      'tradingsymbol': 'NIFTY',
      'symboltoken': symbolTokenNifty,
      'transactiontype': 'SELL',
      'exchange': 'NFO',
      'ordertype': 'MARKET',
      'producttype': product,
      'duration': 'DAY',
      'quantity': qty
    };
    appendLog('Placing SELL order...');
    String res = await api.placeOrder(order);
    appendLog('Order response: $res');
  }
} catch (e) {
  appendLog('Error: $e');
}

} }

// ----------------------------- // UI // ----------------------------- void main() { runApp(ChangeNotifierProvider(create: (_) => AppState(), child: MyApp())); }

class MyApp extends StatelessWidget { @override Widget build(BuildContext context) { return MaterialApp( title: 'Nifty Algo', theme: ThemeData.dark().copyWith( primaryColor: Colors.tealAccent, scaffoldBackgroundColor: Color(0xFF0B0E13), cardColor: Color(0xFF111317), textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Inter'), ), home: HomeScreen(), ); } }

class HomeScreen extends StatefulWidget { @override _HomeScreenState createState() => _HomeScreenState(); }

class _HomeScreenState extends State<HomeScreen> { final TextEditingController _client = TextEditingController(); final TextEditingController _api = TextEditingController(); final TextEditingController _pwd = TextEditingController();

@override Widget build(BuildContext context) { final state = Provider.of<AppState>(context); return Scaffold( appBar: AppBar( title: Text('Nifty 5m Algo — Dark'), backgroundColor: Colors.black, actions: [ IconButton( onPressed: () => showSettings(context), icon: Icon(Icons.settings)), ], ), body: Padding( padding: const EdgeInsets.all(12.0), child: Column( crossAxisAlignment: CrossAxisAlignment.stretch, children: [ Card( child: Padding( padding: const EdgeInsets.all(12.0), child: Column( crossAxisAlignment: CrossAxisAlignment.stretch, children: [ Text('Angel One Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), SizedBox(height: 8), TextField(controller: _client, decoration: InputDecoration(labelText: 'Client ID', border: OutlineInputBorder())), SizedBox(height: 8), TextField(controller: _api, decoration: InputDecoration(labelText: 'API Key', border: OutlineInputBorder())), SizedBox(height: 8), TextField(controller: _pwd, decoration: InputDecoration(labelText: 'Password', border: OutlineInputBorder(), obscureText: true)), SizedBox(height: 8), ElevatedButton( onPressed: () async { bool ok = await state.login(_client.text.trim(), _api.text.trim(), _pwd.text.trim()); final snack = SnackBar(content: Text(ok ? 'Login successful' : 'Login failed')); ScaffoldMessenger.of(context).showSnackBar(snack); }, child: Text('Generate Token / Login')) ], ), ), ), SizedBox(height: 12), Card( child: Padding( padding: const EdgeInsets.all(12.0), child: Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [ Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text('Algo Status', style: TextStyle(fontWeight: FontWeight.bold)), SizedBox(height: 6), Text(state.running ? 'Running' : 'Stopped') ], ), Row( children: [ ElevatedButton( onPressed: state.running ? null : () => state.startAlgo(), child: Text('Start')), SizedBox(width: 8), ElevatedButton(onPressed: state.running ? () => state.stopAlgo() : null, child: Text('Stop')) ], ) ], ), ), ), SizedBox(height: 12), Card( child: Padding( padding: const EdgeInsets.all(12.0), child: Column( crossAxisAlignment: CrossAxisAlignment.stretch, children: [ Text('Quick Controls', style: TextStyle(fontWeight: FontWeight.bold)), SizedBox(height: 8), Row( children: [ Expanded(child: Text('Quantity: ${state.qty}')), IconButton( onPressed: () { state.qty = (state.qty + 25); state.appendLog('Qty set to ${state.qty}'); state.notifyListeners(); }, icon: Icon(Icons.add)), IconButton( onPressed: () { state.qty = (state.qty - 25).clamp(1, 10000); state.appendLog('Qty set to ${state.qty}'); state.notifyListeners(); }, icon: Icon(Icons.remove)), ], ), SizedBox(height: 8), Text('Product: ${state.product}'), SizedBox(height: 6), ElevatedButton(onPressed: () { state.product = state.product == 'MIS' ? 'NRML' : 'MIS'; state.appendLog('Product set to ${state.product}'); state.notifyListeners(); }, child: Text('Toggle Product')) ], ), ), ), SizedBox(height: 12), Expanded( child: Card( child: Padding( padding: const EdgeInsets.all(12.0), child: SingleChildScrollView( reverse: true, child: Text(state.logs, style: TextStyle(fontFamily: 'monospace')), ), ), )) ], ), ), ); }

void showSettings(BuildContext ctx) { final state = Provider.of<AppState>(ctx, listen: false); showModalBottomSheet(context: ctx, backgroundColor: Color(0xFF0B0E13), builder: (c) { return Padding( padding: const EdgeInsets.all(12.0), child: Column( mainAxisSize: MainAxisSize.min, children: [ Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)), SizedBox(height: 8), ListTile( title: Text('Timeframe: 5 minute', style: TextStyle(color: Colors.white)), subtitle: Text('Fixed for this build', style: TextStyle(color: Colors.white70)), ), ListTile( title: Text('Symbol Token (NIFTY)', style: TextStyle(color: Colors.white)), subtitle: Text('${state.symbolTokenNifty}', style: TextStyle(color: Colors.white70)), trailing: IconButton(onPressed: () async { final ctrl = TextEditingController(text: state.symbolTokenNifty); final res = await showDialog(context: ctx, builder: (_) => AlertDialog( title: Text('Edit Symbol Token'), content: TextField(controller: ctrl), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')), TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text('Save'))], )); if (res != null) { state.symbolTokenNifty = res; state.appendLog('Symbol token updated to ${res}'); } }, icon: Icon(Icons.edit)), ), SizedBox(height: 8), ElevatedButton(onPressed: () => Navigator.pop(ctx), child: Text('Close')) ], ), ); }); } }
