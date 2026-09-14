import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RasaDiagApp());
}

class RasaDiagApp extends StatelessWidget {
  const RasaDiagApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RASA DIAG',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Vazirmatn',
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0B10),
      ),
      home: const LicenseGate(),
    );
  }
}

/* ============================================================
   ECU PROFILE
   ============================================================ */

class EcuProfile {
  final String manufacturer;
  final String model;
  final String family;
  final String protocol;
  final String protocolCommand;
  final String header;
  final String functionalHeader;

  const EcuProfile({
    required this.manufacturer,
    required this.model,
    required this.family,
    required this.protocol,
    required this.protocolCommand,
    required this.header,
    required this.functionalHeader,
  });

  String get displayName => '$manufacturer - $model';
}

/* ============================================================
   VEHICLE / ECU DATABASE
   ============================================================ */

const List<EcuProfile> ecuProfiles = [
  EcuProfile(
    manufacturer: 'ایران خودرو / سایپا',
    model: 'Siemens / SSAT',
    family: 'KWP',
    protocol: 'ISO 14230 KWP Fast Init',
    protocolCommand: 'ATSP5',
    header: '8111F1',
    functionalHeader: '81',
  ),

  EcuProfile(
    manufacturer: 'ایران خودرو',
    model: 'Sagem / Valeo S2000 / PL4',
    family: 'KWP',
    protocol: 'ISO 14230 KWP 5-Baud',
    protocolCommand: 'ATSP4',
    header: '8111F1',
    functionalHeader: '81',
  ),

  EcuProfile(
    manufacturer: 'پژو 206 / رانا',
    model: 'Bosch ME7.4.4 / ME7.4.9',
    family: 'KWP',
    protocol: 'ISO 14230 KWP',
    protocolCommand: 'ATSP5',
    header: '8111F1',
    functionalHeader: '81',
  ),

  EcuProfile(
    manufacturer: 'ایران خودرو',
    model: 'Bosch ME17 / Easy-U',
    family: 'UDS',
    protocol: 'ISO 15765-4 CAN 11bit 500k',
    protocolCommand: 'ATSP6',
    header: '7E0',
    functionalHeader: '7DF',
  ),

  EcuProfile(
    manufacturer: 'MVM / Chery / Phenix',
    model: 'UDS CAN',
    family: 'UDS',
    protocol: 'ISO 15765-4 CAN 11bit 500k',
    protocolCommand: 'ATSP6',
    header: '7E0',
    functionalHeader: '7DF',
  ),

  EcuProfile(
    manufacturer: 'کرمان موتور',
    model: 'JAC / KMC Bosch / Delphi',
    family: 'UDS',
    protocol: 'ISO 15765-4 CAN 11bit 500k',
    protocolCommand: 'ATSP6',
    header: '7E0',
    functionalHeader: '7DF',
  ),

  EcuProfile(
    manufacturer: 'بهمن / هایما / برلیانس / چانگان',
    model: 'CAN 500k',
    family: 'UDS',
    protocol: 'ISO 15765-4 CAN 11bit 500k',
    protocolCommand: 'ATSP6',
    header: '7E0',
    functionalHeader: '7DF',
  ),

  EcuProfile(
    manufacturer: 'عمومی',
    model: 'OBD-II',
    family: 'OBD',
    protocol: 'Automatic',
    protocolCommand: 'ATSP0',
    header: '7DF',
    functionalHeader: '7DF',
  ),
];

/* ============================================================
   DTC DATABASE
   ============================================================ */

const Map<String, String> dtcDescriptions = {
  'P0100': 'مدار سنسور MAF / جریان هوا',
  'P0105': 'مدار سنسور MAP',
  'P0110': 'مدار سنسور دمای هوای ورودی IAT',
  'P0115': 'مدار سنسور دمای مایع خنک‌کننده ECT',
  'P0120': 'مدار سنسور موقعیت دریچه گاز TPS',
  'P0130': 'مدار سنسور اکسیژن Bank 1 Sensor 1',
  'P0136': 'مدار سنسور اکسیژن Bank 1 Sensor 2',
  'P0200': 'خطای مدار انژکتورها',
  'P0300': 'احتراق ناقص تصادفی / چند سیلندر',
  'P0335': 'مدار سنسور موقعیت میل‌لنگ CKP',
  'P0340': 'مدار سنسور موقعیت میل‌سوپاپ CMP',
  'P0420': 'بازده پایین کاتالیست',
  'P0443': 'مدار شیر purge سیستم EVAP',
  'P0500': 'خطای سنسور سرعت خودرو',
  'P0560': 'ولتاژ سیستم خودرو',
  'P0606': 'خطای پردازنده ECU',
};

/* ============================================================
   DIAGNOSTIC DATA
   ============================================================ */

class LiveData {
  double? rpm;
  double? speed;
  double? coolant;
  double? throttle;
  double? engineLoad;
  double? intakeAir;
  double? oxygen;
  double? battery;

  LiveData copy() {
    return LiveData()
      ..rpm = rpm
      ..speed = speed
      ..coolant = coolant
      ..throttle = throttle
      ..engineLoad = engineLoad
      ..intakeAir = intakeAir
      ..oxygen = oxygen
      ..battery = battery;
  }
}

class DtcItem {
  final String code;
  final String description;

  const DtcItem({
    required this.code,
    required this.description,
  });
}

/* ============================================================
   LICENSE GATE
   ============================================================ */

class LicenseGate extends StatefulWidget {
  const LicenseGate({super.key});

  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> {
  final TextEditingController _controller = TextEditingController();

  bool _checking = true;
  bool _licensed = false;

  @override
  void initState() {
    super.initState();
    _loadLicense();
  }

  Future<void> _loadLicense() async {
    final prefs = await SharedPreferences.getInstance();

    final active = prefs.getBool('license_active') ?? false;

    if (!mounted) return;

    setState(() {
      _licensed = active;
      _checking = false;
    });
  }

  Future<void> _activate() async {
    final key = _controller.text.trim();

    if (key.length < 8) {
      _showMessage('کد فعال‌سازی معتبر نیست');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('license_active', true);

    if (!mounted) return;

    setState(() {
      _licensed = true;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_licensed) {
      return const DiagnosticHome();
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.car_repair,
                      size: 80,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'RASA DIAG',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Professional Automotive Diagnostic',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        labelText: 'کد فعال‌سازی',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _activate,
                        icon: const Icon(Icons.key),
                        label: const Text('فعال‌سازی'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ============================================================
   MAIN DIAGNOSTIC HOME
   ============================================================ */

class DiagnosticHome extends StatefulWidget {
  const DiagnosticHome({super.key});

  @override
  State<DiagnosticHome> createState() => _DiagnosticHomeState();
}

class _DiagnosticHomeState extends State<DiagnosticHome>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _inputSubscription;

  final StringBuffer _rxBuffer = StringBuffer();

  bool _connecting = false;
  bool _connected = false;
  bool _demoMode = false;
  bool _isBusy = false;

  String _adapterInfo = 'متصل نیست';
  String _protocolInfo = '-';

  EcuProfile? _selectedProfile;

  String _ecuModel = 'شناسایی نشده';
  String _ecuSoftware = 'نامشخص';
  String _vin = 'نامشخص';

  LiveData _liveData = LiveData();

  final List<DtcItem> _dtcs = [];

  Timer? _liveTimer;

  final TextEditingController _terminalController =
      TextEditingController();

  final List<String> _terminalLog = [];

  final Map<String, Completer<String>> _waiters = {};

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 7,
      vsync: this,
    );

    _selectedProfile = ecuProfiles.last;
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _inputSubscription?.cancel();
    _connection?.dispose();
    _tabController.dispose();
    _terminalController.dispose();

    super.dispose();
  }

  /* ==========================================================
     BLUETOOTH PERMISSIONS
     ========================================================== */

  Future<bool> _requestBluetoothPermissions() async {
    if (Theme.of(context).platform == TargetPlatform.android) {
      final scan = await Permission.bluetoothScan.request();
      final connect = await Permission.bluetoothConnect.request();

      return scan.isGranted && connect.isGranted;
    }

    return true;
  }

  /* ==========================================================
     BLUETOOTH DEVICES
     ========================================================== */

  Future<void> _selectBluetoothDevice() async {
    if (_connecting) return;

    final granted = await _requestBluetoothPermissions();

    if (!granted) {
      _showMessage(
        'دسترسی Bluetooth برای اتصال لازم است.',
      );
      return;
    }

    final bluetooth = FlutterBluetoothSerial.instance;

    final enabled = await bluetooth.isEnabled ?? false;

    if (!enabled) {
      _showMessage(
        'ابتدا Bluetooth گوشی را روشن کنید.',
      );
      return;
    }

    final devices = await bluetooth.getBondedDevices();

    if (!mounted) return;

    if (devices.isEmpty) {
      _showMessage(
        'هیچ دستگاه Bluetooth جفت‌شده‌ای پیدا نشد.',
      );
      return;
    }

    final selected = await showDialog<BluetoothDevice>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('انتخاب آداپتور دیاگ'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (context, index) {
                final device = devices[index];

                return ListTile(
                  leading: const Icon(
                    Icons.bluetooth,
                  ),
                  title: Text(
                    device.name ?? 'Unknown',
                  ),
                  subtitle: Text(
                    device.address,
                  ),
                  onTap: () {
                    Navigator.pop(
                      context,
                      device,
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );

    if (selected == null) return;

    await _connectToDevice(selected);
  }

  /* ==========================================================
     CONNECT
     ========================================================== */

  Future<void> _connectToDevice(
    BluetoothDevice device,
  ) async {
    if (_connecting) return;

    setState(() {
      _connecting = true;
    });

    try {
      await _disconnect();

      final connection =
          await BluetoothConnection.toAddress(
        device.address,
      );

      _connection = connection;

      _inputSubscription =
          connection.input?.listen(
        _onDataReceived,
        onDone: () {
          if (mounted) {
            setState(() {
              _connected = false;
              _connecting = false;
            });
          }
        },
        onError: (_) {
          if (mounted) {
            setState(() {
              _connected = false;
              _connecting = false;
            });
          }
        },
      );

      setState(() {
        _connected = true;
        _connecting = false;
        _adapterInfo =
            '${device.name ?? 'Bluetooth'} - ${device.address}';
      });

      await _initializeAdapter();

      _showMessage(
        'آداپتور با موفقیت متصل شد.',
      );
    } catch (e) {
      await _disconnect();

      if (mounted) {
        setState(() {
          _connecting = false;
          _connected = false;
        });

        _showMessage(
          'خطا در اتصال: $e',
        );
      }
    }
  }

  /* ==========================================================
     DISCONNECT
     ========================================================== */

  Future<void> _disconnect() async {
    _liveTimer?.cancel();
    _liveTimer = null;

    await _inputSubscription?.cancel();
    _inputSubscription = null;

    try {
      await _connection?.finish();
    } catch (_) {}

    _connection = null;

    for (final waiter in _waiters.values) {
      if (!waiter.isCompleted) {
        waiter.complete('');
      }
    }

    _waiters.clear();

    if (mounted) {
      setState(() {
        _connected = false;
        _connecting = false;
      });
    }
  }

  /* ==========================================================
     RX DATA
     ========================================================== */

  void _onDataReceived(Uint8List data) {
    final text = ascii.decode(
      data,
      allowInvalid: true,
    );

    _rxBuffer.write(text);

    _processReceiveBuffer();
  }

  void _processReceiveBuffer() {
    while (true) {
      final value = _rxBuffer.toString();

      final index = value.indexOf('>');

      if (index < 0) {
        return;
      }

      final frame = value.substring(
        0,
        index,
      );

      _rxBuffer.clear();
      _rxBuffer.write(
        value.substring(index + 1),
      );

      final cleaned = frame.trim();

      if (cleaned.isEmpty) {
        continue;
      }

      _terminalLog.add(
        '< $cleaned',
      );

      if (_terminalLog.length > 200) {
        _terminalLog.removeAt(0);
      }

      _resolveWaiter(cleaned);

      if (mounted) {
        setState(() {});
      }
    }
  }

  /* ==========================================================
     WAITERS
     ========================================================== */

  void _resolveWaiter(String response) {
    if (_waiters.isEmpty) return;

    final keys = _waiters.keys.toList();

    for (final key in keys) {
      final waiter = _waiters[key];

      if (waiter == null || waiter.isCompleted) {
        _waiters.remove(key);
        continue;
      }

      if (_responseMatches(
        key,
        response,
      )) {
        waiter.complete(response);
        _waiters.remove(key);
        return;
      }
    }

    if (_waiters.length == 1) {
      final key = _waiters.keys.first;
      final waiter = _waiters[key];

      if (waiter != null && !waiter.isCompleted) {
        waiter.complete(response);
        _waiters.remove(key);
      }
    }
  }

  bool _responseMatches(
    String command,
    String response,
  ) {
    final cmd = command
        .replaceAll(' ', '')
        .toUpperCase();

    final res = response
        .replaceAll(' ', '')
        .toUpperCase();

    if (res.contains('NO DATA')) return true;
    if (res.contains('ERROR')) return true;
    if (res.contains('?')) return true;

    if (cmd.startsWith('01')) {
      if (cmd.length >= 4) {
        final pid = cmd.substring(2, 4);

        return res.contains(
          '41$pid',
        );
      }
    }

    if (cmd == '03') {
      return res.contains('43') ||
          res.contains('NO DATA');
    }

    if (cmd == '04') {
      return res.contains('44') ||
          res.contains('OK');
    }

    return true;
  }

  /* ==========================================================
     SEND RAW
     ========================================================== */

  Future<void> _sendRaw(
    String command,
  ) async {
    if (_connection == null) {
      throw Exception(
        'Bluetooth connected نیست',
      );
    }

    final cmd = command.trim();

    if (cmd.isEmpty) return;

    _terminalLog.add(
      '> $cmd',
    );

    if (_terminalLog.length > 200) {
      _terminalLog.removeAt(0);
    }

    final bytes = Uint8List.fromList(
      ascii.encode('$cmd\r'),
    );

    _connection!.output.add(bytes);

    await _connection!.output.allSent;
  }

  /* ==========================================================
     SEND AND WAIT
     ========================================================== */

  Future<String> _sendAndWait(
    String command, {
    Duration timeout =
        const Duration(seconds: 3),
  }) async {
    if (_connection == null) {
      return '';
    }

    final cmd = command.trim();

    final completer = Completer<String>();

    _waiters[cmd] = completer;

    await _sendRaw(cmd);

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          _waiters.remove(cmd);
          return '';
        },
      );
    } catch (_) {
      _waiters.remove(cmd);
      return '';
    }
  }

  /* ==========================================================
     ADAPTER INITIALIZATION
     ========================================================== */

  Future<void> _initializeAdapter() async {
    if (!_connected) return;

    final commands = <String>[
      'ATZ',
      'ATE0',
      'ATL0',
      'ATS0',
      'ATH1',
      'ATI',
      'ATAT1',
      'ATSP0',
      'ATDP',
    ];

    for (final command in commands) {
      await _sendAndWait(
        command,
        timeout: const Duration(seconds: 4),
      );

      await Future.delayed(
        const Duration(milliseconds: 150),
      );
    }

    final protocol =
        await _sendAndWait('ATDP');

    if (protocol.isNotEmpty) {
      _protocolInfo = protocol.trim();
    }

    await _identifyVehicle();
  }

  /* ==========================================================
     SELECT ECU PROFILE
     ========================================================== */

  Future<void> _applyProfile(
    EcuProfile profile,
  ) async {
    if (!_connected) {
      _showMessage(
        'ابتدا به آداپتور متصل شوید.',
      );
      return;
    }

    setState(() {
      _selectedProfile = profile;
      _ecuModel = profile.model;
    });

    await _sendAndWait(
      profile.protocolCommand,
    );

    await Future.delayed(
      const Duration(milliseconds: 200),
    );

    if (profile.family != 'OBD') {
      await _sendAndWait(
        'ATSH ${profile.header}',
      );
    }

    final protocol =
        await _sendAndWait('ATDP');

    if (protocol.isNotEmpty) {
      setState(() {
        _protocolInfo = protocol.trim();
      });
    }

    _showMessage(
      'پروفایل ${profile.displayName} اعمال شد.',
    );
  }

  /* ==========================================================
     VEHICLE IDENTIFICATION
     ========================================================== */

  Future<void> _identifyVehicle() async {
    if (!_connected) return;

    final profile = _selectedProfile;

    if (profile != null &&
        profile.family == 'KWP') {
      await _sendAndWait(
        profile.protocolCommand,
      );

      await _sendAndWait(
        'ATSH ${profile.header}',
      );
    }

    final protocol =
        await _sendAndWait('ATDP');

    if (protocol.isNotEmpty) {
      _protocolInfo = protocol.trim();
    }

    String vin = '';

    final vinResponse =
        await _sendAndWait(
      '0902',
      timeout: const Duration(seconds: 5),
    );

    if (vinResponse.isNotEmpty) {
      vin = _decodeObdAscii(
        vinResponse,
        service: '4902',
      );
    }

    if (vin.isNotEmpty) {
      _vin = vin;
    }

    final ecuNameResponse =
        await _sendAndWait(
      '090A',
      timeout: const Duration(seconds: 4),
    );

    final ecuName = _decodeObdAscii(
      ecuNameResponse,
      service: '490A',
    );

    if (ecuName.isNotEmpty) {
      _ecuModel = ecuName;
    } else if (profile != null) {
      _ecuModel = profile.model;
    } else {
      _ecuModel = 'ECU OBD-II';
    }

    if (mounted) {
      setState(() {});
    }
  }

  /* ==========================================================
     OBD ASCII DECODER
     ========================================================== */

  String _decodeObdAscii(
    String response, {
    required String service,
  }) {
    final cleaned = response
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('>', ' ')
        .trim();

    final normalized =
        cleaned.toUpperCase();

    final start =
        normalized.indexOf(service);

    if (start < 0) {
      return '';
    }

    final hexPart =
        normalized.substring(start + service.length);

    final hexTokens = RegExp(
      r'[0-9A-F]{2}',
    ).allMatches(hexPart);

    final bytes = <int>[];

    for (final match in hexTokens) {
      final value = int.tryParse(
        match.group(0)!,
        radix: 16,
      );

      if (value != null &&
          value >= 0x20 &&
          value <= 0x7E) {
        bytes.add(value);
      }
    }

    if (bytes.isEmpty) {
      return '';
    }

    return String.fromCharCodes(bytes).trim();
  }
}
/* ============================================================
   LIVE DATA
   ============================================================ */

Future<void> _readLiveData() async {
  if (!_connected || _isBusy) return;

  _isBusy = true;

  try {
    final data = LiveData();

    final rpm = await _sendAndWait(
      '010C',
      timeout: const Duration(seconds: 2),
    );

    data.rpm = _parseRpm(rpm);

    final speed = await _sendAndWait(
      '010D',
      timeout: const Duration(seconds: 2),
    );

    data.speed = _parseSpeed(speed);

    final coolant = await _sendAndWait(
      '0105',
      timeout: const Duration(seconds: 2),
    );

    data.coolant = _parseTemperature(
      coolant,
      '4105',
    );

    final throttle = await _sendAndWait(
      '0111',
      timeout: const Duration(seconds: 2),
    );

    data.throttle = _parsePercentage(
      throttle,
      '4111',
    );

    final load = await _sendAndWait(
      '0104',
      timeout: const Duration(seconds: 2),
    );

    data.engineLoad = _parsePercentage(
      load,
      '4104',
    );

    final intake = await _sendAndWait(
      '010F',
      timeout: const Duration(seconds: 2),
    );

    data.intakeAir = _parseTemperature(
      intake,
      '410F',
    );

    final oxygen = await _sendAndWait(
      '0114',
      timeout: const Duration(seconds: 2),
    );

    data.oxygen = _parseOxygen(
      oxygen,
    );

    final battery = await _sendAndWait(
      'ATRV',
      timeout: const Duration(seconds: 2),
    );

    data.battery = _parseBattery(
      battery,
    );

    if (mounted) {
      setState(() {
        _liveData = data;
      });
    }
  } finally {
    _isBusy = false;
  }
}

/* ============================================================
   LIVE DATA TIMER
   ============================================================ */

void _startLiveData() {
  _liveTimer?.cancel();

  if (!_connected) {
    return;
  }

  _liveTimer = Timer.periodic(
    const Duration(seconds: 1),
    (_) async {
      await _readLiveData();
    },
  );

  _readLiveData();
}

void _stopLiveData() {
  _liveTimer?.cancel();
  _liveTimer = null;
}

/* ============================================================
   OBD PARSING
   ============================================================ */

List<int> _extractHexBytes(
  String response,
) {
  final cleaned = response
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ')
      .replaceAll('>', ' ')
      .replaceAll(':', ' ')
      .toUpperCase();

  final matches = RegExp(
    r'\b[0-9A-F]{2}\b',
  ).allMatches(cleaned);

  final bytes = <int>[];

  for (final match in matches) {
    final value = int.tryParse(
      match.group(0)!,
      radix: 16,
    );

    if (value != null) {
      bytes.add(value);
    }
  }

  return bytes;
}

double? _parseRpm(
  String response,
) {
  final bytes = _extractHexBytes(
    response,
  );

  for (var i = 0; i < bytes.length - 3; i++) {
    if (bytes[i] == 0x41 &&
        bytes[i + 1] == 0x0C) {
      final a = bytes[i + 2];
      final b = bytes[i + 3];

      return ((a * 256) + b) / 4.0;
    }
  }

  return null;
}

double? _parseSpeed(
  String response,
) {
  final bytes = _extractHexBytes(
    response,
  );

  for (var i = 0; i < bytes.length - 2; i++) {
    if (bytes[i] == 0x41 &&
        bytes[i + 1] == 0x0D) {
      return bytes[i + 2].toDouble();
    }
  }

  return null;
}

double? _parseTemperature(
  String response,
  String service,
) {
  final serviceBytes = _hexPairList(
    service,
  );

  if (serviceBytes.length != 2) {
    return null;
  }

  final bytes = _extractHexBytes(
    response,
  );

  for (var i = 0; i < bytes.length - 2; i++) {
    if (bytes[i] == serviceBytes[0] &&
        bytes[i + 1] == serviceBytes[1]) {
      return bytes[i + 2] - 40.0;
    }
  }

  return null;
}

double? _parsePercentage(
  String response,
  String service,
) {
  final serviceBytes = _hexPairList(
    service,
  );

  if (serviceBytes.length != 2) {
    return null;
  }

  final bytes = _extractHexBytes(
    response,
  );

  for (var i = 0; i < bytes.length - 2; i++) {
    if (bytes[i] == serviceBytes[0] &&
        bytes[i + 1] == serviceBytes[1]) {
      return bytes[i + 2] * 100.0 / 255.0;
    }
  }

  return null;
}

double? _parseOxygen(
  String response,
) {
  final bytes = _extractHexBytes(
    response,
  );

  for (var i = 0; i < bytes.length - 3; i++) {
    if (bytes[i] == 0x41 &&
        bytes[i + 1] == 0x14) {
      final a = bytes[i + 2];
      final b = bytes[i + 3];

      return a / 200.0;
    }
  }

  return null;
}

double? _parseBattery(
  String response,
) {
  final normalized = response
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ')
      .replaceAll('>', ' ')
      .trim();

  final match = RegExp(
    r'([0-9]+(?:\.[0-9]+)?)',
  ).firstMatch(normalized);

  if (match == null) {
    return null;
  }

  return double.tryParse(
    match.group(1)!,
  );
}

List<int> _hexPairList(
  String value,
) {
  final result = <int>[];

  final clean = value
      .replaceAll(' ', '')
      .toUpperCase();

  for (var i = 0; i + 1 < clean.length; i += 2) {
    final byte = int.tryParse(
      clean.substring(i, i + 2),
      radix: 16,
    );

    if (byte != null) {
      result.add(byte);
    }
  }

  return result;
}

/* ============================================================
   DTC SCAN
   ============================================================ */

Future<void> _scanDtc() async {
  if (!_connected) {
    _showMessage(
      'ابتدا به خودرو متصل شوید.',
    );
    return;
  }

  if (_isBusy) return;

  _isBusy = true;

  try {
    final response = await _sendAndWait(
      '03',
      timeout: const Duration(seconds: 5),
    );

    final parsed = _parseObdDtcs(
      response,
    );

    if (mounted) {
      setState(() {
        _dtcs
          ..clear()
          ..addAll(parsed);
      });
    }

    if (parsed.isEmpty) {
      _showMessage(
        'خطایی از نوع OBD-II پیدا نشد.',
      );
    } else {
      _showMessage(
        '${parsed.length} کد خطا پیدا شد.',
      );
    }
  } finally {
    _isBusy = false;
  }
}

/* ============================================================
   CLEAR DTC
   ============================================================ */

Future<void> _clearDtc() async {
  if (!_connected) {
    _showMessage(
      'ابتدا به خودرو متصل شوید.',
    );
    return;
  }

  final confirmed =
      await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text(
          'پاک کردن خطاها',
        ),
        content: const Text(
          'این عملیات کدهای خطای ذخیره‌شده را پاک می‌کند. '
          'آیا مطمئن هستید؟',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(
                context,
                false,
              );
            },
            child: const Text(
              'انصراف',
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                context,
                true,
              );
            },
            child: const Text(
              'پاک کردن',
            ),
          ),
        ],
      );
    },
  );

  if (confirmed != true) {
    return;
  }

  final response = await _sendAndWait(
    '04',
    timeout: const Duration(seconds: 5),
  );

  if (response.contains('44') ||
      response.contains('OK')) {
    setState(() {
      _dtcs.clear();
    });

    _showMessage(
      'درخواست پاک کردن خطا ارسال شد.',
    );
  } else {
    _showMessage(
      'ECU پاسخ مثبت برای پاک کردن خطا نداد.',
    );
  }
}

/* ============================================================
   DTC DECODER
   ============================================================ */

List<DtcItem> _parseObdDtcs(
  String response,
) {
  final bytes = _extractHexBytes(
    response,
  );

  final result = <DtcItem>[];

  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] != 0x43) {
      continue;
    }

    for (
      var j = i + 1;
      j + 1 < bytes.length;
      j += 2
    ) {
      final a = bytes[j];
      final b = bytes[j + 1];

      if (a == 0 && b == 0) {
        continue;
      }

      final code = _decodeDtc(
        a,
        b,
      );

      if (code == null) {
        continue;
      }

      if (result.any(
        (item) => item.code == code,
      )) {
        continue;
      }

      result.add(
        DtcItem(
          code: code,
          description:
              dtcDescriptions[code] ??
                  'شرح این کد در بانک اطلاعاتی موجود نیست.',
        ),
      );
    }

    break;
  }

  return result;
}

String? _decodeDtc(
  int a,
  int b,
) {
  final first =
      (a >> 6) & 0x03;

  const prefixes = [
    'P',
    'C',
    'B',
    'U',
  ];

  final prefix =
      prefixes[first];

  final digit2 =
      (a >> 4) & 0x03;

  final digit3 =
      a & 0x0F;

  final digit4 =
      (b >> 4) & 0x0F;

  final digit5 =
      b & 0x0F;

  return '$prefix'
      '$digit2'
      '${digit3.toRadixString(16).toUpperCase()}'
      '${digit4.toRadixString(16).toUpperCase()}'
      '${digit5.toRadixString(16).toUpperCase()}';
}

/* ============================================================
   ECU INFORMATION
   ============================================================ */

Future<void> _readEcuInformation() async {
  if (!_connected) {
    _showMessage(
      'ابتدا به آداپتور متصل شوید.',
    );
    return;
  }

  await _identifyVehicle();

  final software =
      await _sendAndWait(
    '090A',
    timeout: const Duration(seconds: 4),
  );

  final decoded =
      _decodeObdAscii(
    software,
    service: '490A',
  );

  if (decoded.isNotEmpty) {
    setState(() {
      _ecuSoftware = decoded;
    });
  }

  final protocol =
      await _sendAndWait(
    'ATDP',
    timeout: const Duration(seconds: 3),
  );

  if (protocol.isNotEmpty) {
    setState(() {
      _protocolInfo =
          protocol.trim();
    });
  }
}

/* ============================================================
   ODOMETER
   ============================================================ */

Future<void> _readOdometer() async {
  /*
   * عمداً از PID عمومی 01A6 به عنوان کیلومتر واقعی
   * استفاده نمی‌شود.
   *
   * کیلومتر واقعی خودرو وابسته به ECU / BCM / IPC
   * و DID یا سرویس اختصاصی همان خودرو است.
   *
   * بنابراین تا زمانی که تعریف دقیق ECU مشخص نشده
   * مقدار جعلی نمایش داده نمی‌شود.
   */

  _showMessage(
    'کارکرد واقعی برای این ECU هنوز با تعریف اختصاصی فعال نشده است.',
  );
}

/* ============================================================
   ACTUATOR SAFETY
   ============================================================ */

Future<void> _runActuator(
  String name,
) async {
  if (!_connected) {
    _showMessage(
      'ابتدا به ECU متصل شوید.',
    );
    return;
  }

  /*
   * هیچ فرمان حدسی 2F / 30 / 31 / KWP
   * به ECU ارسال نمی‌شود.
   *
   * برای اجرای واقعی عملگر باید:
   *
   * 1. ECU دقیق شناسایی شود.
   * 2. سرویس و DID/Routine همان ECU مشخص باشد.
   * 3. پاسخ مثبت ECU بررسی شود.
   * 4. پیش‌شرط‌های ایمنی بررسی شوند.
   * 5. فرمان توقف و timeout وجود داشته باشد.
   */

  final confirmed =
      await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text(
          'عملگر',
        ),
        content: Text(
          'عملگر «$name» برای ECU فعلی '
          'هنوز فرمان معتبر و تأییدشده ندارد.\n\n'
          'برای جلوگیری از ارسال فرمان اشتباه '
          'به ECU، عملیات متوقف شد.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(
                context,
                true,
              );
            },
            child: const Text(
              'متوجه شدم',
            ),
          ),
        ],
      );
    },
  );

  if (confirmed == true) {
    return;
  }
}

/* ============================================================
   DEMO MODE
   ============================================================ */

void _toggleDemoMode() {
  setState(() {
    _demoMode = !_demoMode;
  });

  if (_demoMode) {
    _liveData = LiveData()
      ..rpm = 850
      ..speed = 0
      ..coolant = 86
      ..throttle = 7
      ..engineLoad = 18
      ..intakeAir = 32
      ..oxygen = 0.72
      ..battery = 13.9;

    _ecuModel =
        'DEMO ECU - RASA DIAG';

    _protocolInfo =
        'DEMO / OBD-II';

    _vin =
        'DEMO-VIN-000000000';

    _ecuSoftware =
        'DEMO SOFTWARE 1.0';
  } else {
    _liveData = LiveData();

    _ecuModel =
        'شناسایی نشده';

    _protocolInfo = '-';

    _vin =
        'نامشخص';

    _ecuSoftware =
        'نامشخص';
  }
}

/* ============================================================
   TERMINAL
   ============================================================ */

Future<void> _sendTerminalCommand() async {
  final command =
      _terminalController.text.trim();

  if (command.isEmpty) {
    return;
  }

  _terminalController.clear();

  if (!_connected) {
    _showMessage(
      'آداپتور متصل نیست.',
    );
    return;
  }

  await _sendRaw(
    command,
  );

  if (mounted) {
    setState(() {});
  }
}

/* ============================================================
   MESSAGE
   ============================================================ */

void _showMessage(
  String message,
) {
  if (!mounted) return;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration:
            const Duration(seconds: 2),
      ),
    );
}
