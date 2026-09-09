import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CanDiagApp());
}

class CanDiagApp extends StatelessWidget {
  const CanDiagApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'دستگاه دیاگ CAN و OBD2',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        cardColor: const Color(0xFF161B22),
        primaryColor: const Color(0xFF58A6FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF58A6FF),
          secondary: Color(0xFF238636),
          error: Color(0xFFDA3633),
        ),
      ),
      home: const MainDiagScreen(),
    );
  }
}

// -------------------------------------------------------------
// بانک اطلاعات ترجمه کدهای خطای رایج به فارسی
// -------------------------------------------------------------
final Map<String, String> dtcDescriptions = {
  'P0100': 'ایراد در مدار سنسور جریان جرمی هوا (MAF)',
  'P0105': 'ایراد در مدار سنسور فشار منیفولد (MAP)',
  'P0110': 'ایراد در سنسور دمای هوای ورودی (IAT)',
  'P0115': 'ایراد در مدار سنسور دمای آب خنک‌کننده (ECT)',
  'P0120': 'ایراد در سنسور موقعیت دریچه گاز (TPS)',
  'P0130': 'ایراد در مدار سنسور اکسیژن بالا (سنسور ۱)',
  'P0136': 'ایراد در مدار سنسور اکسیژن پایین (سنسور ۲)',
  'P0200': 'ایراد در مدار انژکتورها',
  'P0300': 'احتراق ناقص تصادفی در سیلندرها (Misfire)',
  'P0335': 'ایراد در سنسور موقعیت میل‌لنگ (دور موتور)',
  'P0340': 'ایراد در سنسور موقعیت میل‌سوپاپ',
  'P0420': 'کاهش راندمان کاتالیست اگزوز',
  'P0443': 'ایراد در شیر برقی تخلیه کنیستر (EVAP)',
  'P0500': 'ایراد در سنسور سرعت خودرو (VSS)',
  'P0560': 'ایراد در ولتاژ سیستم برق / دینام',
  'P0606': 'ایراد در پردازنده مرکزی ایسیو (ECU Processor)',
};

class MainDiagScreen extends StatefulWidget {
  const MainDiagScreen({super.key});

  @override
  State<MainDiagScreen> createState() => _MainDiagScreenState();
}

class _MainDiagScreenState extends State<MainDiagScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  UsbPort? _port;
  bool _isConnected = false;
  bool _isDemoMode = false;
  Timer? _liveDataTimer;
  String _serialBuffer = '';

  // پارامترهای زنده (Live Data)
  int _rpm = 0;
  int _speed = 0;
  int _coolant = 0;
  double _battery = 0.0;
  int _throttle = 0;

  // کدهای خطا (DTCs)
  final List<String> _detectedFaults = [];
  bool _isLoadingFaults = false;

  // لاگ ترمینال CAN
  final List<String> _canLogs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  // --- مدیریت اتصال USB ---
  Future<void> _toggleUsbConnection() async {
    if (_isConnected) {
      _disconnect();
      return;
    }

    if (_isDemoMode) _toggleDemo(false);

    List<UsbDevice> devices = await UsbSerial.listDevices();
    if (devices.isEmpty) {
      _showToast('هیچ دانگل USB متصل شده‌ای یافت نشد. کابل OTG را بررسی کنید.');
      return;
    }

    try {
      UsbDevice device = devices.first;
      _port = await device.create();
      bool opened = await _port!.open();
      if (!opened) {
        _showToast('امکان دسترسی به پورت USB وجود ندارد.');
        return;
      }

      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        115200, // نرخ استاندارد سریال
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      setState(() => _isConnected = true);
      _showToast('دانگل USB CAN با موفقیت متصل شد.');

      // گوش دادن به داده‌های ورودی
      _port!.inputStream!.listen(_processUsbData, onDone: _disconnect);

      // مقداردهی اولیه SLCAN به سرعت 500Kbps خودرو
      _sendRawCanCommand('S6\r'); // 500kbps CAN speed
      _sendRawCanCommand('O\r');  // Open CAN Channel

      // شروع درخواست دوره‌ای داده‌های زنده
      _startLivePolling();
    } catch (e) {
      _showToast('خطا در اتصال: $e');
      _disconnect();
    }
  }

  void _disconnect() {
    _liveDataTimer?.cancel();
    _port?.close();
    _port = null;
    setState(() {
      _isConnected = false;
      _isLoadingFaults = false;
    });
  }

  // پردازش داده‌های متنی دریافتی از دانگل
  void _processUsbData(Uint8List data) {
    _serialBuffer += String.fromCharCodes(data);
    while (_serialBuffer.contains('\r') || _serialBuffer.contains('\n')) {
      int idxCR = _serialBuffer.indexOf('\r');
      int idxLF = _serialBuffer.indexOf('\n');
      int splitIdx = (idxCR != -1 && idxLF != -1) ? (idxCR < idxLF ? idxCR : idxLF) : (idxCR != -1 ? idxCR : idxLF);

      String rawFrame = _serialBuffer.substring(0, splitIdx).trim();
      _serialBuffer = _serialBuffer.substring(splitIdx + 1);

      if (rawFrame.isNotEmpty) {
        _handleIncomingCanLine(rawFrame);
      }
    }
  }

  void _handleIncomingCanLine(String frame) {
    setState(() {
      if (_canLogs.length > 50) _canLogs.removeAt(0);
      _canLogs.add(frame);
    });

    // نمونه فریم دریافت پاسخ استاندارد OBD-II:
    // t7E8 8 04 41 0C 1A F8 00 00 00 (دور موتور)
    if (frame.startsWith('t7E8') || frame.startsWith('t7E9') || frame.contains('41') || frame.contains('43')) {
      _parseObdResponse(frame);
    }
  }

  // رمزگشایی کدهای برگشتی از ECU
  void _parseObdResponse(String frame) {
    try {
      // نرمال‌سازی فریم
      String clean = frame.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
      if (clean.length < 8) return;

      // جستجوی بایت پاسخ سرویس (مثلا 41 برای Live Data)
      int idx41 = clean.indexOf('41');
      if (idx41 != -1 && clean.length >= idx41 + 4) {
        String pid = clean.substring(idx41 + 2, idx41 + 4).toUpperCase();
        String payload = clean.substring(idx41 + 4);

        setState(() {
          switch (pid) {
            case '0C': // دور موتور RPM = ((A*256)+B)/4
              if (payload.length >= 4) {
                int a = int.parse(payload.substring(0, 2), radix: 16);
                int b = int.parse(payload.substring(2, 4), radix: 16);
                _rpm = ((a * 256) + b) ~/ 4;
              }
              break;
            case '0D': // سرعت Vehicle Speed = A
              if (payload.length >= 2) {
                _speed = int.parse(payload.substring(0, 2), radix: 16);
              }
              break;
            case '05': // دمای آب Engine Coolant Temp = A - 40
              if (payload.length >= 2) {
                _coolant = int.parse(payload.substring(0, 2), radix: 16) - 40;
              }
              break;
            case '11': // زاویه دریچه گاز Throttle = (A*100)/255
              if (payload.length >= 2) {
                int a = int.parse(payload.substring(0, 2), radix: 16);
                _throttle = ((a * 100) / 255).round();
              }
              break;
            case '42': // ولتاژ باتری Control Module Voltage = ((A*256)+B)/1000
              if (payload.length >= 4) {
                int a = int.parse(payload.substring(0, 2), radix: 16);
                int b = int.parse(payload.substring(2, 4), radix: 16);
                _battery = ((a * 256) + b) / 1000.0;
              }
              break;
          }
        });
      }

      // پاسخ سرویس 03 (خواندن خطاها - کد 43)
      int idx43 = clean.indexOf('43');
      if (idx43 != -1) {
        String dtcData = clean.substring(idx43 + 4);
        _parseDtcPayload(dtcData);
      }
    } catch (_) {}
  }

  void _parseDtcPayload(String dtcBytes) {
    List<String> codes = [];
    for (int i = 0; i + 4 <= dtcBytes.length; i += 4) {
      String hexWord = dtcBytes.substring(i, i + 4);
      if (hexWord == '0000') continue;

      int b1 = int.parse(hexWord.substring(0, 2), radix: 16);
      int b2 = int.parse(hexWord.substring(2, 4), radix: 16);

      String prefix = '';
      switch ((b1 & 0xC0) >> 6) {
        case 0: prefix = 'P'; break;
        case 1: prefix = 'C'; break;
        case 2: prefix = 'B'; break;
        case 3: prefix = 'U'; break;
      }
      String fullDtc = '$prefix${(b1 & 0x3F).toRadixString(16).padLeft(2, '0')}${b2.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
      codes.add(fullDtc);
    }

    setState(() {
      _detectedFaults.clear();
      _detectedFaults.addAll(codes);
      _isLoadingFaults = false;
    });
  }

  // ارسال فریم‌های استاندارد CAN به ایسیو
  void _sendRawCanCommand(String cmd) {
    if (_port != null && _isConnected) {
      _port!.write(Uint8List.fromList(cmd.codeUnits));
    }
  }

  void _sendObdRequest(String serviceAndPid) {
    // بسته استاندارد درخواست دیاگ به آیدی ایسیو (0x7DF / 0x7E0):
    // t7DF 8 [Length] [Service] [PID] 00 00 00 00 00\r
    int len = serviceAndPid.length ~/ 2;
    String frame = 't7DF80$len$serviceAndPid' + '00' * (7 - len) + '\r';
    _sendRawCanCommand(frame);
  }

  void _startLivePolling() {
    _liveDataTimer?.cancel();
    int step = 0;
    _liveDataTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
      if (!_isConnected) return;
      // ارسال نوبتی درخواست پارامترهای موتور
      switch (step % 4) {
        case 0: _sendObdRequest('010C'); break; // دور موتور
        case 1: _sendObdRequest('010D'); break; // سرعت
        case 2: _sendObdRequest('0105'); break; // دمای آب
        case 3: _sendObdRequest('0111'); break; // دریچه گاز
      }
      step++;
    });
  }

  // --- درخواست خواندن خطاها ---
  void _readDtcCodes() {
    if (_isDemoMode) {
      setState(() {
        _isLoadingFaults = true;
        Future.delayed(const Duration(seconds: 1), () {
          setState(() {
            _detectedFaults.clear();
            _detectedFaults.addAll(['P0115', 'P0300', 'P0443']);
            _isLoadingFaults = false;
          });
        });
      });
      return;
    }

    if (!_isConnected) {
      _showToast('ابتدا دانگل را متصل کنید.');
      return;
    }

    setState(() {
      _isLoadingFaults = true;
      _detectedFaults.clear();
    });

    // ارسال درخواست Mode 03 (خواندن خطاهای ثبت شده)
    _sendObdRequest('03');
    // مهلت انتظار پاسخ ایسیو
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isLoadingFaults) {
        setState(() => _isLoadingFaults = false);
      }
    });
  }

  // --- درخواست پاک کردن خطاها ---
  void _clearDtcCodes() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پاک‌سازی حافظه خطاهای ایسیو'),
        content: const Text('آیا از پاک کردن تمام خطاهای موتور (Clear DTCs) اطمینان دارید؟ سوئیچ خودرو باید باز باشد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDA3633)),
            onPressed: () {
              Navigator.pop(ctx);
              if (_isDemoMode) {
                setState(() => _detectedFaults.clear());
                _showToast('خطاها با موفقیت پاک شدند (حالت شبیه‌ساز).');
                return;
              }
              // ارسال درخواست Mode 04 برای ریست خطاهای ذخیره شده
              _sendObdRequest('04');
              setState(() => _detectedFaults.clear());
              _showToast('دستور پاک کردن خطاها به ایسیو ارسال شد.');
            },
            child: const Text('پاک کردن خطاها'),
          )
        ],
      ),
    );
  }

  // --- ارسال دستور تست عملگرها ---
  void _executeActuatorTest(String name, String servicePayload) {
    if (!_isConnected && !_isDemoMode) {
      _showToast('برای تست عملگرها باید به خودرو متصل باشید.');
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تست عملگر: $name'),
        content: Text('دستور فعال‌سازی $name به مدت ۵ ثانیه به ایسیو ارسال می‌شود. آیا ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF238636)),
            onPressed: () {
              Navigator.pop(ctx);
              if (_isConnected) {
                // ارسال فریم UDS IO Control / Routine Test به ایسیو
                _sendRawCanCommand('t7E08' + servicePayload + '\r');
              }
              _showToast('دستور فعال‌سازی $name ارسال شد.');
            },
            child: const Text('شروع تست'),
          )
        ],
      ),
    );
  }

  // حالت شبیه‌ساز داخلی برای تست بدون خودرو
  void _toggleDemo(bool enable) {
    setState(() => _isDemoMode = enable);
    _liveDataTimer?.cancel();
    if (enable) {
      if (_isConnected) _disconnect();
      _liveDataTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
        setState(() {
          _rpm = (800 + (t.tick * 60) % 4500).toInt();
          _speed = ((_rpm / 40)).clamp(0, 180).toInt();
          _coolant = 89;
          _battery = 14.1;
          _throttle = (_speed / 1.8).clamp(0, 100).toInt();
        });
      });
      _showToast('حالت شبیه‌ساز فعال شد.');
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _disconnect();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('دیاگ تخصصی خودرو (CAN / OBD2)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF161B22),
        actions: [
          IconButton(
            icon: Icon(_isDemoMode ? Icons.play_circle : Icons.play_circle_outline,
                color: _isDemoMode ? Colors.amber : Colors.grey),
            tooltip: 'شبیه‌ساز تستی',
            onPressed: () => _toggleDemo(!_isDemoMode),
          ),
          IconButton(
            icon: Icon(
              _isConnected ? Icons.usb : Icons.usb_off,
              color: _isConnected ? const Color(0xFF58A6FF) : Colors.grey,
            ),
            tooltip: 'اتصال دانگل USB',
            onPressed: _toggleUsbConnection,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF58A6FF),
          tabs: const [
            Tab(icon: Icon(Icons.speed), text: 'داده زنده'),
            Tab(icon: Icon(Icons.warning_amber_rounded), text: 'کدهای خطا'),
            Tab(icon: Icon(Icons.touch_app), text: 'تست عملگرها'),
            Tab(icon: Icon(Icons.terminal), text: 'ترمینال CAN'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLiveDataTab(),
          _buildDtcFaultsTab(),
          _buildActuatorTestTab(),
          _buildTerminalTab(),
        ],
      ),
    );
  }

  // ۱. تب پارامترهای زنده موتور
  Widget _buildLiveDataTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildGaugeCard('دور موتور', '$_rpm', 'RPM', const Color(0xFF58A6FF))),
              const SizedBox(width: 12),
              Expanded(child: _buildGaugeCard('سرعت خودرو', '$_speed', 'km/h', const Color(0xFF3FB950))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildGaugeCard('دمای آب موتور', '$_coolant', '°C', _coolant > 98 ? const Color(0xFFDA3633) : const Color(0xFFF0883E))),
              const SizedBox(width: 8),
              Expanded(child: _buildGaugeCard('ولتاژ باتری', _battery.toStringAsFixed(1), 'V', const Color(0xFFD29922))),
              const SizedBox(width: 8),
              Expanded(child: _buildGaugeCard('دریچه گاز', '$_throttle', '%', const Color(0xFFA371F7))),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isConnected ? 'وضعیت: متصل به پورت CAN خودرو' : (_isDemoMode ? 'وضعیت: در حال اجرای شبیه‌ساز' : 'وضعیت: قطع اتصال USB'),
                  style: TextStyle(color: _isConnected || _isDemoMode ? Colors.greenAccent : Colors.redAccent, fontSize: 13),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // ۲. تب خواندن و پاک کردن خطاهای ایسیو
  Widget _buildDtcFaultsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF238636),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _isLoadingFaults ? null : _readDtcCodes,
                  icon: const Icon(Icons.search),
                  label: const Text('خواندن خطاهای ایسیو'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDA3633),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _detectedFaults.isEmpty ? null : _clearDtcCodes,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('پاک کردن خطاها'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoadingFaults
                ? const Center(child: CircularProgressIndicator())
                : _detectedFaults.isEmpty
                    ? const Center(
                        child: Text('هیچ خطایی ثبت نشده است (یا هنوز دکمه خواندن را نزده‌اید)',
                            style: TextStyle(color: Colors.grey)),
                      )
                    : ListView.builder(
                        itemCount: _detectedFaults.length,
                        itemBuilder: (ctx, i) {
                          final code = _detectedFaults[i];
                          final desc = dtcDescriptions[code] ?? 'کد خطای ناشناخته / اختصاصی کارخانه';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDA3633).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFDA3633)),
                                ),
                                child: Text(code, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                              ),
                              title: Text(desc, style: const TextStyle(fontSize: 14)),
                              subtitle: const Text('وضعیت: دائم / ذخیره شده در حافظه ECU', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ),
                          );
                    
