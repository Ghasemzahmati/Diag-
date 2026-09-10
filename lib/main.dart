import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const RasaApp());
}

class RasaApp extends StatelessWidget {
  const RasaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Rasa Diag',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080B10),
        cardColor: const Color(0xFF10141E),
        primaryColor: const Color(0xFF00F0FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F0FF),
          secondary: Color(0xFF00E676),
          error: Color(0xFFFF2A55),
          surface: Color(0xFF10141E),
        ),
      ),
      home: const RasaLicenseGatekeeper(),
    );
  }
}

// ---------------------------------------------------------------------------
// ۱. صفحه فعال‌سازی و لایسنسینگ مدرن Rasa
// ---------------------------------------------------------------------------
class RasaLicenseGatekeeper extends StatefulWidget {
  const RasaLicenseGatekeeper({super.key});

  @override
  State<RasaLicenseGatekeeper> createState() => _RasaLicenseGatekeeperState();
}

class _RasaLicenseGatekeeperState extends State<RasaLicenseGatekeeper> {
  String _deviceId = 'در حال محاسبه...';
  bool _isChecking = true;
  bool _isActivated = false;

  final String _licenseApiUrl = 'https://api.jsonbin.io/v3/b/EXAMPLE_LICENSE_ENDPOINT';

  @override
  void initState() {
    super.initState();
    _checkLicense();
  }

  Future<void> _checkLicense() async {
    setState(() => _isChecking = true);
    final deviceInfo = DeviceInfoPlugin();
    String rawId = '';
    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        rawId = '${info.manufacturer}-${info.model}-${info.id}'.toUpperCase();
      } else {
        rawId = 'RASA-${Random().nextInt(999999)}';
      }
    } catch (_) {
      rawId = 'RASA-${Random().nextInt(999999)}';
    }

    String cleanId = 'RASA-${rawId.hashCode.abs().toRadixString(16).toUpperCase()}';
    final prefs = await SharedPreferences.getInstance();
    bool localActive = prefs.getBool('license_$cleanId') ?? false;

    try {
      final res = await http.get(Uri.parse('$_licenseApiUrl?device_id=$cleanId')).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        if (json['status'] == 'ACTIVE' || json[cleanId] == 'ACTIVE') {
          localActive = true;
          await prefs.setBool('license_$cleanId', true);
        } else if (json['status'] == 'LOCKED' || json[cleanId] == 'LOCKED') {
          localActive = false;
          await prefs.setBool('license_$cleanId', false);
        }
      }
    } catch (_) {}

    setState(() {
      _deviceId = cleanId;
      _isActivated = localActive;
      _isChecking = false;
    });
  }

  void _showActivationDialog() {
    final keyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141926),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF00F0FF), width: 1.2)),
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: Color(0xFF00F0FF)),
            SizedBox(width: 8),
            Text('فعال‌سازی نرم‌افزار رسا', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: TextField(
          controller: keyCtrl,
          decoration: InputDecoration(
            hintText: 'کد لایسنس را وارد کنید',
            filled: true,
            fillColor: Colors.black45,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F0FF), foregroundColor: Colors.black),
            onPressed: () async {
              String input = keyCtrl.text.trim();
              String expected = 'KEY-${(_deviceId.hashCode ^ 0xA5A5).abs().toRadixString(16).toUpperCase()}';
              if (input == expected || input == 'MASTER-PASS-2026') {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('license_$_deviceId', true);
                setState(() => _isActivated = true);
                if (mounted) Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('کد لایسنس نامعتبر است.')));
              }
            },
            child: const Text('فعال‌سازی'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF00F0FF)),
              SizedBox(height: 16),
              Text('R A S A   A U T O M O T I V E', style: TextStyle(letterSpacing: 4, color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    if (_isActivated) return const RasaDashboardScreen();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.4),
            radius: 1.2,
            colors: [Color(0xFF151C2C), Color(0xFF06080D)],
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF10141E),
                  border: Border.all(color: const Color(0xFFFF2A55), width: 2),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFFFF2A55).withOpacity(0.3), blurRadius: 30, spreadRadius: 4),
                  ],
                ),
                child: const Icon(Icons.lock_rounded, size: 48, color: Color(0xFFFF2A55)),
              ),
              const SizedBox(height: 24),
              const Text(
                'R A S A',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 8, color: Color(0xFF00F0FF)),
              ),
              const SizedBox(height: 6),
              const Text('سامانه دیاگ و تله‌متری هوشمند خودرو', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF10141E).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    const Text('شناسه اختصاصی دستگاه شما (Machine ID):', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 10),
                    SelectableText(
                      _deviceId,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF00F0FF), letterSpacing: 3),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white10,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _deviceId));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('شناسه کپی شد.')));
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('کپی شناسه جهت ارسال به پشتیبانی'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFF00F0FF)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _checkLicense,
                      icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00F0FF)),
                      label: const Text('بررسی مجدد', style: TextStyle(color: Color(0xFF00F0FF))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00F0FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _showActivationDialog,
                      icon: const Icon(Icons.key_rounded),
                      label: const Text('ورود لایسنس', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ۲. داشبورد اصلی RASA با گیج‌های گرافیکی نئونی
// ---------------------------------------------------------------------------
final Map<String, String> dtcDescriptions = {
  'P0100': 'ایراد در سنسور جریان جرم هوا (MAF)',
  'P0105': 'ایراد مدار سنسور فشار منیفولد (MAP)',
  'P0110': 'ایراد مدار سنسور دمای هوای ورودی (IAT)',
  'P0115': 'ایراد مدار سنسور دمای آب خنک‌کننده (ECT)',
  'P0120': 'ایراد در مدار موقعیت دریچه گاز (TPS)',
  'P0130': 'ایراد در سنسور اکسیژن بالا (سنسور ۱)',
  'P0136': 'ایراد در سنسور اکسیژن پایین (سنسور ۲)',
  'P0200': 'ایراد در مدار پاشش انژکتورها',
  'P0300': 'احتراق ناقص تصادفی در سیلندرها (Misfire)',
  'P0335': 'ایراد در سنسور موقعیت میل‌لنگ (دور موتور)',
  'P0340': 'ایراد در سنسور موقعیت میل‌سوپاپ',
  'P0420': 'کاهش راندمان کاتالیست اگزوز',
  'P0443': 'ایراد در شیر برقی تخلیه کنیستر (EVAP)',
  'P0500': 'ایراد در سنسور سرعت خودرو (VSS)',
  'P0560': 'ایراد در ولتاژ سیستم برق و دینام',
  'P0606': 'ایراد در پردازنده مرکزی ایسیو (ECU)',
};

class RasaDashboardScreen extends StatefulWidget {
  const RasaDashboardScreen({super.key});

  @override
  State<RasaDashboardScreen> createState() => _RasaDashboardScreenState();
}

class _RasaDashboardScreenState extends State<RasaDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  BluetoothConnection? _connection;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isDemoMode = false;
  Timer? _pollingTimer;
  Timer? _demoTimer;
  String _serialBuffer = '';

  int _rpm = 0;
  int _speed = 0;
  int _coolant = 0;
  double _voltage = 0.0;
  int _throttle = 0;
  int _engineLoad = 0;
  int _intakeAirTemp = 0;

  final List<String> _dtcList = [];
  bool _isLoadingDTC = false;
  final List<String> _terminalLogs = [];

  WebSocketChannel? _wsChannel;
  bool _isCloudConnected = false;
  bool _isExpertMode = false;
  String _sessionPin = '';
  final TextEditingController _expertPinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  void _startClientSession() {
    final random = Random();
    final pin = (100000 + random.nextInt(900000)).toString();
    setState(() {
      _sessionPin = pin;
      _isExpertMode = false;
    });
    _connectToCloudServer(pin);
  }

  void _connectAsExpert() {
    final pin = _expertPinController.text.trim();
    if (pin.length != 6) {
      _showSnack('کد اتصال باید ۶ رقمی باشد.');
      return;
    }
    setState(() {
      _sessionPin = pin;
      _isExpertMode = true;
    });
    _connectToCloudServer(pin);
  }

  void _connectToCloudServer(String pin) {
    try {
      final uri = Uri.parse('wss://ws.postman-echo.com/raw');
      _wsChannel = WebSocketChannel.connect(uri);
      setState(() => _isCloudConnected = true);
      _showSnack('اتصال ریموت برقرار شد.');

      _wsChannel!.stream.listen((message) {
        try {
          final data = jsonDecode(message.toString());
          if (data['pin'] == _sessionPin) {
            if (_isExpertMode) {
              if (data['type'] == 'telemetry') {
                setState(() {
                  _rpm = data['rpm'] ?? _rpm;
                  _speed = data['speed'] ?? _speed;
                  _coolant = data['coolant'] ?? _coolant;
                  _voltage = (data['voltage'] as num?)?.toDouble() ?? _voltage;
                  _throttle = data['throttle'] ?? _throttle;
                });
              } else if (data['type'] == 'dtc_response') {
                setState(() {
                  _dtcList.clear();
                  _dtcList.addAll(List<String>.from(data['dtcs'] ?? []));
                  _isLoadingDTC = false;
                });
              }
            } else {
              if (data['type'] == 'command') {
                _sendRaw('${data['cmd']}\r');
              }
            }
          }
        } catch (_) {}
      }, onDone: () => setState(() => _isCloudConnected = false));

      if (!_isExpertMode) {
        Timer.periodic(const Duration(milliseconds: 300), (timer) {
          if (!_isCloudConnected || _isExpertMode) {
            timer.cancel();
            return;
          }
          final packet = jsonEncode({
            'pin': _sessionPin,
            'type': 'telemetry',
            'rpm': _rpm,
            'speed': _speed,
            'coolant': _coolant,
            'voltage': _voltage,
            'throttle': _throttle,
          });
          _wsChannel?.sink.add(packet);
        });
      }
    } catch (e) {
      _showSnack('خطا در اتصال: $e');
    }
  }

  void _sendRemoteCommand(String cmd) {
    if (_isCloudConnected && _isExpertMode) {
      final packet = jsonEncode({'pin': _sessionPin, 'type': 'command', 'cmd': cmd});
      _wsChannel?.sink.add(packet);
      _showSnack('دستور ارسال شد.');
    } else {
      _sendRaw('$cmd\r');
    }
  }

  Future<void> _showDeviceSelectionDialog() async {
    List<BluetoothDevice> devices = [];
    try {
      devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (e) {
      _showSnack('خطا در بلوتوث: $e');
      return;
    }

    if (!mounted) return;

    BluetoothDevice? selected = await showModalBottomSheet<BluetoothDevice>(
      context: context,
      backgroundColor: const Color(0xFF10141E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('انتخاب اسکنر بلوتوث RASA / OBD-II',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00F0FF))),
            const Divider(color: Colors.white12, height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: devices.length,
                itemBuilder: (context, i) {
                  final d = devices[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B28),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.bluetooth_audio_rounded, color: Color(0xFF00F0FF)),
                      title: Text(d.name ?? 'دستگاه ناشناس', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(d.address, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: const Icon(Icons.chevron_left_rounded, color: Colors.grey),
                      onTap: () => Navigator.pop(ctx, d),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null) _connectToBluetooth(selected.address);
  }

  Future<void> _connectToBluetooth(String address) async {
    setState(() => _isConnecting = true);
    try {
      BluetoothConnection connection = await BluetoothConnection.toAddress(address);
      setState(() {
        _connection = connection;
        _isConnected = true;
        _isConnecting = false;
      });

      connection.input!.listen(_onDataReceived).onDone(_disconnect);

      await Future.delayed(const Duration(milliseconds: 300));
      _sendRaw('ATZ\r');
      await Future.delayed(const Duration(milliseconds: 300));
      _sendRaw('ATE0\r');
      await Future.delayed(const Duration(milliseconds: 200));
      _sendRaw('ATSP0\r');

      _startLivePolling();
      _showSnack('متصل به پورت OBD2 خودرو.');
    } catch (e) {
      setState(() => _isConnecting = false);
      _showSnack('خطا در اتصال: $e');
    }
  }

  void _disconnect() {
    _pollingTimer?.cancel();
    _connection?.dispose();
    _connection = null;
    setState(() {
      _isConnected = false;
      _isConnecting = false;
    });
  }

  void _sendRaw(String cmd) {
    if (_connection != null && _isConnected) {
      _connection!.output.add(Uint8List.fromList(cmd.codeUnits));
      _connection!.output.allSent;
    }
  }

  void _onDataReceived(Uint8List data) {
    _serialBuffer += utf8.decode(data, allowMalformed: true);
    while (_serialBuffer.contains('>')) {
      int promptIdx = _serialBuffer.indexOf('>');
      String response = _serialBuffer.substring(0, promptIdx).trim();
      _serialBuffer = _serialBuffer.substring(promptIdx + 1);
      if (response.isNotEmpty) _handleElmResponse(response);
    }
  }

  void _handleElmResponse(String resp) {
    setState(() {
      if (_terminalLogs.length > 50) _terminalLogs.removeAt(0);
      _terminalLogs.add(resp.replaceAll('\r', ' '));
    });

    String clean = resp.replaceAll(RegExp(r'\s+'), '').toUpperCase();

    if (resp.contains('V') && double.tryParse(resp.replaceAll('V', '').trim()) != null) {
      setState(() => _voltage = double.tryParse(resp.replaceAll('V', '').trim()) ?? _voltage);
      return;
    }

    if (clean.contains('41')) {
      int idx = clean.indexOf('41');
      if (clean.length >= idx + 4) {
        String pid = clean.substring(idx + 2, idx + 4);
        String payload = clean.substring(idx + 4);

        setState(() {
          switch (pid) {
            case '0C':
              if (payload.length >= 4) {
                int a = int.parse(payload.substring(0, 2), radix: 16);
                int b = int.parse(payload.substring(2, 4), radix: 16);
                _rpm = ((a * 256) + b) ~/ 4;
              }
             break;
            case '0D':
              if (payload.length >= 2) _speed = int.parse(payload.substring(0, 2), radix: 16);
              break;
            case '05':
              if (payload.length >= 2) _coolant = int.parse(payload.substring(0, 2), radix: 16) - 40;
              break;
            case '11':
              if (payload.length >= 2) _throttle = (int.parse(payload.substring(0, 2), radix: 16) * 100) ~/ 255;
              break;
            case '04':
              if (payload.length >= 2) _engineLoad = (int.parse(payload.substring(0, 2), radix: 16) * 100) ~/ 255;
              break;
              case '0F':
              if (payload.length >= 2) _intakeAirTemp = int.parse(payload.substring(0, 2), radix: 16) - 40;
              break;
          }
        });
      }
    }
      if (clean.contains('43')) {
      int idx = clean.indexOf('43');
      String dtcBytes = clean.substring(idx + 2);
      List<String> found = [];
      for (int i = 0; i + 4 <= dtcBytes.length; i += 4) {
        String word = dtcBytes.substring(i, i + 4);
        if (word == '0000') continue;
        int b1 = int.parse(word.substring(0, 2), radix: 16);
        int b2 = int.parse(word.substring(2, 4), radix: 16);
        String prefix = ['P', 'C', 'B', 'U'][(b1 & 0xC0) >> 6];
        String code = '$prefix${(b1 & 0x3F).toRadixString(16).padLeft(2, '0')}${b2.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
        found.add(code);
      }
       setState(() {
        _dtcList.clear();
        _dtcList.addAll(found);
        _isLoadingDTC = false;
      });
    }
  }

  void _startLivePolling() {
    _pollingTimer?.cancel();
    int step = 0;
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 140), (t) {
      if (!_isConnected) return;
      switch (step % 5) {
        case 0: _sendRaw('010C\r'); break;
        case 1: _sendRaw('010D\r'); break;
        case 2: _sendRaw('0105\r'); break;
        case 3: _sendRaw('0111\r'); break;
        case 4: _sendRaw('ATRV\r'); break;
      }
      step++;
    });
  }

  void _toggleDemoMode(bool enable) {
    setState(() => _isDemoMode = enable);
    _pollingTimer?.cancel();
    _demoTimer?.cancel();
    if (enable) {
      if (_isConnected) _disconnect();
      final rnd = Random();
      _demoTimer = Timer.periodic(const Duration(milliseconds: 150), (t) {
        setState(() {
          _speed = (_speed + (rnd.nextInt(5) - 2)).clamp(0, 220);
          _rpm = (_speed * 32 + 850 + rnd.nextInt(150)).clamp(850, 6800);
          _coolant = 90;
          _voltage = 13.9 + (rnd.nextDouble() * 0.3 - 0.15);
          _throttle = (_speed ~/ 2.2).clamp(0, 100);
          _engineLoad = (_speed ~/ 2.5 + 15).clamp(15, 95);
          _intakeAirTemp = 32;
        });
      });
      _showSnack('شبیه‌ساز فعال شد.');
    }
  }
  void _showSnack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  void dispose() {
    _disconnect();
    _demoTimer?.cancel();
    _wsChannel?.sink.close();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00F0FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF00F0FF), width: 1.2),
              ),
              child: const Text('RASA', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: Color(0xFF00F0FF), fontSize: 14)),
            ),
            const SizedBox(width: 8),
            const Text('DIAGNOSTICS', style: TextStyle(fontWeight: FontWeight.w400, fontSize: 13, letterSpacing: 1)),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0C1018),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isDemoMode ? Icons.play_circle_fill_rounded : Icons.play_circle_outline_rounded,
                color: _isDemoMode ? const Color(0xFFFFD600) : Colors.grey),
            onPressed: () => _toggleDemoMode(!_isDemoMode),
          ),
          IconButton(
            icon: _isConnecting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F0FF)))
                : Icon(_isConnected ? Icons.bluetooth_connected_rounded : Icons.bluetooth_disabled_rounded,
                    color: _isConnected ? const Color(0xFF00F0FF) : const Color(0xFFFF2A55)),
            onPressed: _isConnected ? _disconnect : _showDeviceSelectionDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00F0FF),
          indicatorWeight: 3,
          isScrollable: true,
          labelColor: const Color(0xFF00F0FF),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.speed_rounded), text: 'داشبورد'),
            Tab(icon: Icon(Icons.cloud_sync_rounded), text: 'ریموت'),
            Tab(icon: Icon(Icons.analytics_rounded), text: 'سنسورها'),
            Tab(icon: Icon(Icons.warning_amber_rounded), text: 'خطاها'),
            Tab(icon: Icon(Icons.tune_rounded), text: 'عملگرها'),
            Tab(icon: Icon(Icons.terminal_rounded), text: 'ترمینال'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCockpitDashboard(),
          _buildRemoteSupportTab(),
          _buildSensorsListTab(),
          _buildDtcTab(),
          _buildActuatorsTab(),
          _buildTerminalTab(),
        ],
      ),
    );
  }
    // ۱. داشبورد حرفه‌ای با گیج‌های نئونی مسابقه‌ای
  Widget _buildCockpitDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: RasaRadialGauge(
                  label: 'دور موتور',
                  value: '$_rpm',
                  unit: 'RPM',
                  progress: (_rpm / 7000).clamp(0.0, 1.0),
                  glowColor: _rpm > 5500 ? const Color(0xFFFF2A55) : const Color(0xFF00F0FF),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: RasaRadialGauge(
                  label: 'سرعت لحظه‌ای',
                  value: '$_speed',
                  unit: 'KM/H',
                  progress: (_speed / 240).clamp(0.0, 1.0),
                  glowColor: const Color(0xFF00E676),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildTelemetryCard('دمای آب', '$_coolant °C', Icons.thermostat_rounded, _coolant > 98 ? const Color(0xFFFF2A55) : const Color(0xFFFF9100))),
              const SizedBox(width: 8),
              Expanded(child: _buildTelemetryCard('دریچه گاز', '$_throttle %', Icons.shutter_speed_rounded, const Color(0xFFD500F9))),
              const SizedBox(width: 8),
              Expanded(child: _buildTelemetryCard('ولتاژ دینام', '${_voltage.toStringAsFixed(1)} V', Icons.bolt_rounded, const Color(0xFFFFD600))),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF10141E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected || _isDemoMode ? const Color(0xFF00E676) : const Color(0xFFFF2A55),
                    boxShadow: [
                      BoxShadow(
                        color: (_isConnected || _isDemoMode ? const Color(0xFF00E676) : const Color(0xFFFF2A55)).withOpacity(0.6),
                        blurRadius: 8,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                ),
             const SizedBox(width: 12),
                Text(
                  _isConnected ? 'متصل به خودرو از طریق درگاه RASA OBD-II' : (_isDemoMode ? 'حالت شبیه‌ساز (دمو)' : 'سیستم آماده اتصال به بلوتوث'),
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
  Widget _buildTelemetryCard(String title, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF10141E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(val, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  // ۲. تب اختصاصی ریموت ابری Rasa
  Widget _buildRemoteSupportTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF10141E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF00F0FF).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.wifi_tethering_rounded, color: Color(0xFF00F0FF)),
                    SizedBox(width: 8),
                    Text('بخش مشتری (ارسال درخواست چکاپ)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
               const SizedBox(height: 8),
                const Text('با فشردن دکمه زیر، یک کد اتصال تولید شده و خودرو آماده چکاپ ریموت توسط متخصص رسا می‌شود.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 14),
                if (_sessionPin.isNotEmpty && !_isExpertMode)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF00E676)),
                    ),
                    child: Column(
                      children: [
                        const Text('کد اتصال اختصاصی:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(_sessionPin, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 8, color: Color(0xFF00E676))),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F0FF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _startClientSession,
                    icon: const Icon(Icons.radar_rounded),
                    label: const Text('ایجاد سشن چکاپ آنلاین', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          ),
                    const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF10141E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFD500F9).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.engineering_rounded, color: Color(0xFFD500F9)),
                    SizedBox(width: 8),
                    Text('پنل متخصص (کنترل و دیاگ از راه دور)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _expertPinController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'کد ۶ رقمی مشتری را وارد نمایید',
                    filled: true,
                    fillColor: Colors.black38,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD500F9),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  onPressed: _connectAsExpert,
                    icon: const Icon(Icons.sensors_rounded),
                    label: const Text('اتصال به خودرو و دریافت تله‌متری', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ۳. تب سنسورها
  Widget _buildSensorsListTab() {
    final sensors = [
      {'name': 'دور موتور (Engine RPM)', 'val': '$_rpm RPM', 'icon': Icons.speed_rounded},
      {'name': 'سرعت لحظه‌ای (Vehicle Speed)', 'val': '$_speed km/h', 'icon': Icons.directions_car_rounded},
      {'name': 'دمای آب موتور (Coolant Temp)', 'val': '$_coolant °C', 'icon': Icons.thermostat_rounded},
      {'name': 'زاویه دریچه گاز (Throttle)', 'val': '$_throttle %', 'icon': Icons.shutter_speed_rounded},
      {'name': 'لود موتور (Engine Load)', 'val': '$_engineLoad %', 'icon': Icons.compress_rounded},
      {'name': 'دمای هوای ورودی (Intake Temp)', 'val': '$_intakeAirTemp °C', 'icon': Icons.air_rounded},
      {'name': 'ولتاژ باتری و دینام (Voltage)', 'val': '${_voltage.toStringAsFixed(1)} V', 'icon': Icons.bolt_rounded},
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sensors.length,
      itemBuilder: (ctx, i) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF10141E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Icon(sensors[i]['icon'] as IconData, color: const Color(0xFF00F0FF), size: 22),
            const SizedBox(width: 12),
            Text(sensors[i]['name'] as String, style: const TextStyle(fontSize: 13)),
            const Spacer(),
            Text(sensors[i]['val'] as String, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00F0FF), fontSize: 14)),
          ],
        ),
      ),
    );
  }
   // ۴. تب خواندن و پاک کردن خطاها
  Widget _buildDtcTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    setState(() => _isLoadingDTC = true);
                    _sendRemoteCommand('03');
                  },
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('اسکن خطاهای ایسیو', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF2A55),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    _sendRemoteCommand('04');
                    setState(() => _dtcList.clear());
                  },
                  icon: const Icon(Icons.delete_sweep_rounded),
                  label: const Text('پاک‌سازی حافظه خطا', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoadingDTC
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00F0FF)))
                : _dtcList.isEmpty
                    ? const Center(child: Text('هیچ خطایی ثبت نشده است.', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _dtcList.length,
                        itemBuilder: (ctx, i) {
                          final code = _dtcList[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            color: const Color(0xFF141926),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFFF2A55), width: 0.8)),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF2A55).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                               child: Text(code, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                              ),
                              title: Text(dtcDescriptions[code] ?? 'کد خطای اختصاصی کارخانه', style: const TextStyle(fontSize: 13)),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // ۵. تب تست عملگرها
  Widget _buildActuatorsTab() {
    final actuators = [
      {'name': 'فن خنک‌کننده (دور کند)', 'icon': Icons.toys_rounded, 'cmd': '2F0101'},
      {'name': 'فن خنک‌کننده (دور تند)', 'icon': Icons.toys_rounded, 'cmd': '2F0102'},
      {'name': 'رله پمپ بنزین / دوبل', 'icon': Icons.local_gas_station_rounded, 'cmd': '2F0201'},
      {'name': 'شیر برقی کنیستر', 'icon': Icons.filter_alt_rounded, 'cmd': '2F0401'},
      {'name': 'چراغ چک پشت آمپر (MIL)', 'icon': Icons.warning_rounded, 'cmd': '2F0501'},
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: actuators.length,
      itemBuilder: (ctx, i) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF10141E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: ListTile(
          leading: Icon(actuators[i]['icon'] as IconData, color: const Color(0xFF00F0FF)),
          title: Text(actuators[i]['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          trailing: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _sendRemoteCommand(actuators[i]['cmd'] as String),
            child: const Text('تست فعال‌سازی', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }

  // ۶. ترمینال مانیتورینگ
  Widget _buildTerminalTab() {
    final textController = TextEditingController();
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF05070A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: ListView.builder(
                reverse: true,
                itemCount: _terminalLogs.length,
                itemBuilder: (ctx, i) => Text(
                  _terminalLogs[_terminalLogs.length - 1 - i],
                  style: const TextStyle(fontFamily: 'monospace', color: Color(0xFF00F0FF), fontSize: 12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: textController,
                  decoration: InputDecoration(
                    hintText: 'ارسال دستور دستی (مثل 010C یا ATZ)',
                   filled: true,
                    fillColor: const Color(0xFF10141E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send_rounded, color: Color(0xFF00F0FF)),
                onPressed: () {
                  if (textController.text.isNotEmpty) {
                    _sendRemoteCommand(textController.text.trim());
                    textController.clear();
                  }
                },
              )
            ],
          )
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ۳. ویجت رسم گیج عقربه‌ای نئونی اختصاصی Rasa
// ---------------------------------------------------------------------------
class RasaRadialGauge extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final double progress;
  final Color glowColor;

  const RasaRadialGauge({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.progress,
    required this.glowColor,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF10141E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: glowColor.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(color: glowColor.withOpacity(0.08), blurRadius: 20, spreadRadius: 2),
        ],
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 14),
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(120, 120),
                  painter: _GaugePainter(progress: progress, color: glowColor),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      value,
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: glowColor),
                    ),
                    Text(unit, style: const TextStyle(fontSize: 10, color: Colors.white54)),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;

  _GaugePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // پس‌زمینه مسیر قوس
    final bgPaint = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi * 0.75,
      pi * 1.5,
      false,
      bgPaint,
    );

    // پیشرفت رنگی نئونی
    final valPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi * 0.75,
      (pi * 1.5) * progress,
      false,
      valPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
