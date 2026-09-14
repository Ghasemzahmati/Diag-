import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const RasaApp());
}

class RasaApp extends StatelessWidget {
  const RasaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RASA DIAG Professional',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080B10),
        cardColor: const Color(0xFF10141E),
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

class RasaLicenseGatekeeper extends StatefulWidget {
  const RasaLicenseGatekeeper({super.key});

  @override
  State<RasaLicenseGatekeeper> createState() =>
      _RasaLicenseGatekeeperState();
}

class _RasaLicenseGatekeeperState
    extends State<RasaLicenseGatekeeper> {
  String _deviceId = 'در حال استخراج...';
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkLicense();
  }

  Future<void> _checkLicense() async {
    try {
      final info = DeviceInfoPlugin();

      String raw;

      if (Platform.isAndroid) {
        final a = await info.androidInfo;

        raw =
            '${a.manufacturer}-${a.model}-${a.id}'
                .toUpperCase();
      } else {
        raw =
            'RASA-${DateTime.now().millisecondsSinceEpoch}';
      }

      _deviceId =
          'RASA-${raw.hashCode.abs().toRadixString(16).toUpperCase()}';

      final prefs =
          await SharedPreferences.getInstance();

      final local = prefs.getBool(
            'license_${_deviceId.replaceAll('-', '_')}',
          ) ??
          false;

      if (!mounted) return;

      setState(() {
        _checking = false;
      });

      if (local) {
        _openApp();
      } else {
        await _showActivation();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }

      await _showActivation();
    }
  }

  Future<void> _showActivation() async {
    final controller = TextEditingController();

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            'فعال‌سازی RASA DIAG',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'شناسه دستگاه:',
              ),
              const SizedBox(height: 8),
              SelectableText(
                _deviceId,
                style: const TextStyle(
                  color: Color(0xFF00F0FF),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'کلید فعال‌سازی',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('بعداً'),
            ),
            FilledButton(
              onPressed: () async {
                /*
                 * برای نسخه تجاری باید اعتبارسنجی
                 * کلید در سرور انجام شود.
                 */
                if (controller.text.trim().length < 8) {
                  return;
                }

                final prefs =
                    await SharedPreferences.getInstance();

                await prefs.setBool(
                  'license_${_deviceId.replaceAll('-', '_')}',
                  true,
                );

                if (!mounted) return;

                Navigator.pop(context);

                _openApp();
              },
              child: const Text('فعال‌سازی'),
            ),
          ],
        );
      },
    );
  }

  void _openApp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            const RasaDashboardScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _checking
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.car_repair_rounded,
                    size: 72,
                    color: Color(0xFF00F0FF),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'RASA DIAG PROFESSIONAL',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _deviceId,
                    style: const TextStyle(
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
      ),
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
  final String? header;
  final String? functionalHeader;

  const EcuProfile({
    required this.manufacturer,
    required this.model,
    required this.family,
    required this.protocol,
    this.header,
    this.functionalHeader,
  });

  String get title =>
      '$manufacturer $model';
}

/* ============================================================
   ECU DATABASE
   ============================================================ */

const ecuProfiles = <EcuProfile>[
  EcuProfile(
    manufacturer: 'Bosch',
    model: 'ME7.4.x',
    family: 'Peugeot / Iran Khodro',
    protocol: 'KWP2000',
    header: 'ATSH 8111F1',
  ),

  EcuProfile(
    manufacturer: 'Sagem / Valeo',
    model: 'S2000 / PL4',
    family: 'Iran Khodro / Saipa',
    protocol: 'KWP2000',
    header: 'ATSH 8111F1',
  ),

  EcuProfile(
    manufacturer: 'Siemens / SSAT',
    model: 'KWP',
    family: 'Iran Khodro / Saipa',
    protocol: 'KWP2000',
    header: 'ATSH 8111F1',
  ),

  EcuProfile(
    manufacturer: 'Bosch',
    model: 'ME17 / Easy-U',
    family: 'Dena / Peugeot / Samand',
    protocol: 'CAN 500K',
    header: 'ATSH 7E0',
  ),

  EcuProfile(
    manufacturer: 'Chery / MVM',
    model: 'UDS CAN',
    family: 'MVM / Fownix',
    protocol: 'UDS ISO-TP',
    header: 'ATSH 7E0',
  ),

  EcuProfile(
    manufacturer: 'Bosch / Delphi',
    model: 'CAN',
    family: 'JAC / KMC',
    protocol: 'CAN 500K',
    header: 'ATSH 7E0',
  ),

  EcuProfile(
    manufacturer: 'Haima / Changan / Brilliance',
    model: 'CAN',
    family: 'Bahman / Chinese',
    protocol: 'CAN 500K',
    header: 'ATSH 7E0',
  ),

  EcuProfile(
    manufacturer: 'Generic',
    model: 'OBD-II',
    family: 'All supported vehicles',
    protocol: 'OBD-II',
    functionalHeader: 'ATSH 7DF',
  ),
];

/* ============================================================
   DTC DATABASE
   ============================================================ */

const dtcDescriptions = <String, String>{
  'P0100':
      'مدار سنسور جریان هوای جرمی (MAF)',
  'P0105':
      'مدار سنسور فشار منیفولد (MAP)',
  'P0110':
      'مدار سنسور دمای هوای ورودی (IAT)',
  'P0115':
      'مدار سنسور دمای مایع خنک‌کننده (ECT)',
  'P0120':
      'مدار موقعیت دریچه گاز (TPS)',
  'P0130':
      'مدار سنسور اکسیژن Bank 1 Sensor 1',
  'P0136':
      'مدار سنسور اکسیژن Bank 1 Sensor 2',
  'P0200':
      'مدار انژکتورها',
  'P0300':
      'احتراق ناقص تصادفی',
  'P0335':
      'سنسور موقعیت میل‌لنگ',
  'P0340':
      'سنسور موقعیت میل‌سوپاپ',
  'P0420':
      'راندمان کاتالیست پایین',
  'P0443':
      'شیر برقی EVAP',
  'P0500':
      'سنسور سرعت خودرو',
  'P0560':
      'ولتاژ سیستم برق',
  'P0606':
      'پردازنده ECU',
};

/* ============================================================
   DIAGNOSTIC FRAME
   ============================================================ */

class DiagnosticFrame {
  final String command;
  final String response;
  final DateTime time;

  DiagnosticFrame(
    this.command,
    this.response,
  ) : time = DateTime.now();
}

/* ============================================================
   MAIN DIAGNOSTIC SCREEN
   ============================================================ */

class RasaDashboardScreen extends StatefulWidget {
  const RasaDashboardScreen({super.key});

  @override
  State<RasaDashboardScreen> createState() =>
      _RasaDashboardScreenState();
}

class _RasaDashboardScreenState
    extends State<RasaDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  BluetoothConnection? _connection;

  StreamSubscription<Uint8List>? _serialSub;

  Timer? _pollTimer;
  Timer? _demoTimer;

  final List<String> _logs = [];
  final List<String> _dtcs = [];

  final Map<String, Completer<String>>
      _waiters = {};

  String _buffer = '';

  bool _connected = false;
  bool _connecting = false;
  bool _demo = false;
  bool _requestInFlight = false;
  bool _scanInProgress = false;

  bool _supportsOdometer = false;
  bool _isKwp = false;

  EcuProfile _profile =
      ecuProfiles.last;

  String _protocol = 'Unknown';
  String _ecuModel = 'شناسایی نشده';
  String _ecuSoftware = '---';
  String _vin = '---';
  String _adapterInfo = '---';
  String _connectionStatus =
      'آماده اتصال';

  int _rpm = 0;
  int _speed = 0;
  int _coolant = 0;
  int _throttle = 0;
  int _engineLoad = 0;
  int _iat = 0;

  double _voltage = 0;
  double _o2 = 0;
  double _odometer = 0;

  String _odometerStatus =
      'استعلام نشده';

  String _activeActuator = '';

  bool _loadingDtc = false;
  bool _clearingDtc = false;

  int _pollIndex = 0;

  final TextEditingController
      _terminalController =
      TextEditingController();

  @override
  void initState() {
    super.initState();

    _tabs = TabController(
      length: 7,
      vsync: this,
    );
  }

  /* ==========================================================
     LOG
     ========================================================== */

  void _log(String text) {
    if (!mounted) return;

    setState(() {
      if (_logs.length >= 150) {
        _logs.removeAt(0);
      }

      final time = DateTime.now()
          .toIso8601String()
          .substring(11, 19);

      _logs.add('$time  $text');
    });
  }

  /* ==========================================================
     BLUETOOTH PERMISSION
     ========================================================== */

  Future<bool>
      _requestBluetoothPermissions() async {
    if (!Platform.isAndroid) {
      return true;
    }

    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();

    final connect =
        statuses[
                Permission.bluetoothConnect]
            ?.isGranted ??
            false;

    final scan =
        statuses[
                Permission.bluetoothScan]
            ?.isGranted ??
            false;

    if (!connect || !scan) {
      final location =
          await Permission.location.request();

      if (!location.isGranted &&
          (!connect || !scan)) {
        return false;
      }
    }

    return true;
  }

  /* ==========================================================
     SELECT BLUETOOTH DEVICE
     ========================================================== */

  Future<void>
      _selectBluetoothDevice() async {
    final granted =
        await _requestBluetoothPermissions();

    if (!granted) {
      _snack(
        'مجوزهای لازم بلوتوث صادر نشده است.',
      );
      return;
    }

    List<BluetoothDevice> devices;

    try {
      devices =
          await FlutterBluetoothSerial
              .instance
              .getBondedDevices();
    } catch (e) {
      _snack(
        'خطای دسترسی به بلوتوث: $e',
      );
      return;
    }

    if (!mounted) return;

    final selected =
        await showModalBottomSheet<
            BluetoothDevice>(
      context: context,
      backgroundColor:
          const Color(0xFF10141E),
      builder: (_) {
        return SafeArea(
          child: SizedBox(
            height: min(
              MediaQuery.of(context)
                      .size
                      .height *
                  .65,
              560,
            ),
            child: devices.isEmpty
                ? const Center(
                    child: Text(
                      'دانگل Pair شده‌ای پیدا نشد.',
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.all(
                      12,
                    ),
                    itemCount:
                        devices.length,
                    itemBuilder:
                        (_, index) {
                      final device =
                          devices[index];

                      return ListTile(
                        leading:
                            const Icon(
                          Icons.bluetooth,
                          color:
                              Color(0xFF00F0FF),
                        ),
                        title: Text(
                          device.name ??
                              'OBD Adapter',
                        ),
                        subtitle:
                            Text(
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

    if (selected != null) {
      await _connect(selected);
    }
  }

  /* ==========================================================
     CONNECT
     ========================================================== */

  Future<void> _connect(
    BluetoothDevice device,
  ) async {
    if (_connecting) return;

    await _disconnect();

    setState(() {
      _connecting = true;

      _connectionStatus =
          'در حال اتصال به '
          '${device.name ?? device.address}';
    });

    try {
      final connection =
          await BluetoothConnection
              .toAddress(
        device.address,
      );

      _connection = connection;

      _serialSub =
          connection.input?.listen(
        _onBytes,
        onError: (error) {
          _log('RX ERROR $error');
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _connected = false;
            });
          }
        },
      );

      setState(() {
        _connected = true;
        _connecting = false;

        _connectionStatus =
            'دانگل متصل؛ '
            'در حال شناسایی ECU';
      });

      _log(
        'CONNECTED '
        '${device.name ?? device.address}',
      );

      await _initializeAdapter();

      await _identifyVehicle();

      _startPolling();
    } catch (e) {
      setState(() {
        _connecting = false;
        _connected = false;
        _connectionStatus =
            'خطا در اتصال';
      });

      _snack(
        'اتصال ناموفق: $e',
      );
    }
  }

  /* ==========================================================
     INITIALIZE ELM327
     ========================================================== */

  Future<void>
      _initializeAdapter() async {
    await _sendAndWait(
      'ATZ',
      timeout:
          const Duration(seconds: 3),
      logCommand: true,
    );

    await Future.delayed(
      const Duration(milliseconds: 300),
    );

    await _sendAndWait(
      'ATE0',
      timeout:
          const Duration(seconds: 1),
      logCommand: true,
    );

    await _sendAndWait(
      'ATL0',
      timeout:
          const Duration(seconds: 1),
      logCommand: true,
    );

    await _sendAndWait(
      'ATS0',
      timeout:
          const Duration(seconds: 1),
      logCommand: true,
    );

    await _sendAndWait(
      'ATH1',
      timeout:
          const Duration(seconds: 1),
      logCommand: true,
    );

    final ati =
        await _sendAndWait(
      'ATI',
      timeout:
          const Duration(seconds: 1),
      logCommand: true,
    );

    _adapterInfo =
        _firstUsefulLine(
      ati,
      'ELM/OBD adapter',
    );

    await _sendAndWait(
      'ATAT1',
      timeout:
          const Duration(seconds: 1),
      logCommand: true,
    );

    await _sendAndWait(
      'ATSP0',
      timeout:
          const Duration(seconds: 2),
      logCommand: true,
    );

    final dp =
        await _sendAndWait(
      'ATDP',
      timeout:
          const Duration(seconds: 1),
      logCommand: true,
    );

    _protocol =
        _firstUsefulLine(
      dp,
      'Auto',
    );

    _log(
      'PROTOCOL $_protocol',
    );
  }

  /* ==========================================================
     APPLY ECU PROFILE
     ========================================================== */

  Future<void> _applyProfile(
    EcuProfile profile,
  ) async {
    if (!_connected) {
      _snack(
        'ابتدا به دانگل متصل شوید.',
      );
      return;
    }

    _pollTimer?.cancel();

    setState(() {
      _profile = profile;

      _supportsOdometer = false;

      _odometer = 0;

      _odometerStatus =
          'استعلام نشده';
    });

    String protocolCommand;

    if (profile.protocol ==
        'OBD-II') {
      protocolCommand = 'ATSP0';
    } else if (profile.protocol
        .contains('KWP')) {
      protocolCommand = 'ATSP5';
    } else {
      protocolCommand = 'ATSP6';
    }

    await _sendAndWait(
      protocolCommand,
      timeout:
          const Duration(seconds: 2),
    );

    if (profile.header != null) {
      await _sendAndWait(
        profile.header!,
        timeout:
            const Duration(seconds: 1),
      );
    }

    _startPolling();
  }

  /* ==========================================================
     ECU IDENTIFICATION
     ========================================================== */

  Future<void>
      _identifyVehicle() async {
    if (!_connected ||
        _scanInProgress) {
      return;
    }

    setState(() {
      _scanInProgress = true;

      _connectionStatus =
          'در حال شناسایی ECU';

      _ecuModel =
          'در حال شناسایی...';

      _vin = '---';

      _ecuSoftware = '---';
    });

    try {
      final dp =
          await _sendAndWait(
        'ATDP',
        timeout:
            const Duration(seconds: 2),
      );

      final dpClean =
          dp.toUpperCase();

      _protocol =
          _firstUsefulLine(
        dp,
        'Unknown',
      );

      _isKwp =
          dpClean.contains(
                'ISO 14230',
              ) ||
              dpClean.contains(
                'KWP',
              ) ||
              dpClean.contains(
                'ISO 9141',
              );

      final ecuName =
          await _sendAndWait(
        '090A',
        timeout:
            const Duration(seconds: 2),
      );

      final vin =
          await _sendAndWait(
        '0902',
        timeout:
            const Duration(seconds: 2),
      );

      final name =
          _decodeObdAscii(
        ecuName,
        '4A0A',
      );

      final vinText =
          _decodeObdAscii(
        vin,
        '4902',
      );

      if (name.isNotEmpty) {
        _ecuModel = name;
      }

      if (vinText.isNotEmpty) {
        _vin = vinText;
      }

      if (_profile.header != null &&
          !_isKwp) {
        await _sendAndWait(
          _profile.header!,
          timeout:
              const Duration(seconds: 1),
        );
      }

      final rpm =
          await _sendAndWait(
        '010C',
        timeout:
            const Duration(seconds: 2),
      );

      if (_parsePid(
            rpm,
            '0C',
          ) !=
          null) {
        if (_ecuModel ==
                'در حال شناسایی...' ||
            _ecuModel ==
                'شناسایی نشده') {
          _ecuModel =
              'ECU OBD-II';
        }
      }

      _ecuSoftware =
          'از ECU عمومی قابل تشخیص نیست';

      _connectionStatus =
          'ECU پاسخ‌گو';
    } catch (e) {
      _log(
        'IDENTIFY ERROR $e',
      );

      _ecuModel =
          'شناسایی ناموفق';

      _connectionStatus =
          'دانگل متصل / ECU نامشخص';
    } finally {
      if (mounted) {
        setState(() {
          _scanInProgress = false;
        });
      }
    }
  }

  /* ==========================================================
     FIRST USEFUL LINE
     ========================================================== */

  String _firstUsefulLine(
    String value,
    String fallback,
  ) {
    final lines = value
        .split(RegExp(r'[\r\n]+'))
        .map(
          (e) => e.trim(),
        )
        .where(
          (e) =>
              e.isNotEmpty &&
              e != '>',
        )
        .toList();

    if (lines.isEmpty) {
      return fallback;
    }

    return lines.last;
  }

  /* ==========================================================
     OBD ASCII DECODER
     ========================================================== */

  String _decodeObdAscii(
    String response,
    String positivePrefix,
  ) {
    final clean = response
        .replaceAll(
          RegExp(r'\s+'),
          '',
        )
        .toUpperCase();

    final index =
        clean.indexOf(
      positivePrefix,
    );

    if (index < 0) {
      return '';
    }

    final hex = clean.substring(
      index + positivePrefix.length,
    );

    final bytes = <int>[];

    for (
      int i = 0;
      i + 2 <= hex.length;
      i += 2
    ) {
      final byte =
          int.tryParse(
        hex.substring(i, i + 2),
        radix: 16,
      );

      if (byte == null) {
        break;
      }

      if (byte >= 0x20 &&
          byte <= 0x7E) {
        bytes.add(byte);
      }
    }

    return String.fromCharCodes(
      bytes,
    ).trim();
  }

  /* ==========================================================
     SEND AND WAIT
     ========================================================== */

  Future<String> _sendAndWait(
    String command, {
    Duration timeout =
        const Duration(
      milliseconds: 1500,
    ),
    bool logCommand = false,
  }) async {
    if (!_connected ||
        _connection == null) {
      return '';
    }

    final key = command
        .toUpperCase()
        .replaceAll(
          RegExp(r'\s+'),
          '',
        );

    if (logCommand) {
      _log(
        'TX $command',
      );
    }

    final existing =
        _waiters[key];

    if (existing != null) {
      return existing.future;
    }

    final completer =
        Completer<String>();

    _waiters[key] = completer;

    try {
      _connection!.output.add(
        Uint8List.fromList(
          utf8.encode(
            '$command\r',
          ),
        ),
      );

      await _connection!
          .output
          .allSent;

      final result =
          await completer.future.timeout(
        timeout,
        onTimeout: () => '',
      );

      if (logCommand &&
          result.isNotEmpty) {
        _log(
          'RX $result',
        );
      }

      return result;
    } finally {
      if (identical(
        _waiters[key],
        completer,
      )) {
        _waiters.remove(key);
      }
    }
  }

  /* ==========================================================
     MANUAL TERMINAL
     ========================================================== */

  Future<void> _sendManual(
    String command,
  ) async {
    if (!_connected) {
      _snack(
        'ابتدا به دانگل متصل شوید.',
      );
      return;
    }

    final value =
        command.trim().toUpperCase();

    if (value.isEmpty) {
      return;
    }

    final response =
        await _sendAndWait(
      value,
      timeout:
          const Duration(seconds: 3),
      logCommand: true,
    );

    if (response.isEmpty) {
      _log('TIMEOUT');
    }
  }

  /* ==========================================================
     RECEIVE BYTES
     ========================================================== */

  void _onBytes(
    Uint8List data,
  ) {
    _buffer += utf8.decode(
      data,
      allowMalformed: true,
    );

    while (_buffer.contains('>')) {
      final index =
          _buffer.indexOf('>');

      final response =
          _buffer
              .substring(
                0,
                index,
              )
              .trim();

      _buffer =
          _buffer.substring(
        index + 1,
      );

      if (response.isEmpty) {
        continue;
      }

      _log(
        'RX $response',
      );

      _resolveWaiter(
        response,
      );

      _parseResponse(
        response,
      );
    }
  }

  /* ==========================================================
     RESOLVE RESPONSE
     ========================================================== */

  void _resolveWaiter(
    String response,
  ) {
    final clean = response
        .replaceAll(
          RegExp(r'\s+'),
          '',
        )
        .toUpperCase();

    if (_waiters.isEmpty) {
      return;
    }

    String? key;

    if (clean.contains('41')) {
      final index =
          clean.indexOf('41');

      if (index + 4 <=
          clean.length) {
        key =
            '01${clean.substring(index + 2, index + 4)}';
      }
    } else if (clean.contains('49')) {
      final index =
          clean.indexOf('49');

      if (index + 4 <=
          clean.length) {
        key =
            '09${clean.substring(index + 2, index + 4)}';
      }
    } else if (clean.contains('43')) {
      key = '03';
    } else if (clean.contains('44')) {
      key = '04';
    }

    if (key != null &&
        _waiters.containsKey(key)) {
      final completer =
          _waiters.remove(key)!;

      if (!completer.isCompleted) {
        completer.complete(
          response,
        );
      }

      return;
    }

    /*
     * AT commands generally do not have
     * a PID-based positive response.
     */
    if (_waiters.length == 1) {
      final completer =
          _waiters.values.first;

      if (!completer.isCompleted) {
        completer.complete(
          response,
        );
      }
    }
  }

  /* ==========================================================
     PID PARSER
     ========================================================== */

  int? _parsePid(
    String response,
    String pid,
  ) {
    final clean = response
        .replaceAll(
          RegExp(r'\s+'),
          '',
        )
        .toUpperCase();

    final index =
        clean.indexOf(
      '41$pid',
    );

    if (index < 0) {
      return null;
    }

    final start =
        index + 4;

    if (start + 2 >
        clean.length) {
      return null;
    }

    return int.tryParse(
      clean.substring(
        start,
        start + 2,
      ),
      radix: 16,
    );
  }

  /* ==========================================================
     PARSE RESPONSE
     ========================================================== */

  void _parseResponse(
    String response,
  ) {
    final clean = response
        .replaceAll(
          RegExp(r'\s+'),
          '',
        )
        .toUpperCase();

    if (clean.contains(
          'SEARCHING',
        ) ||
        clean.contains(
          'NO DATA',
        ) ||
        clean.contains(
          'ERROR',
        ) ||
        clean.contains(
          'STOPPED',
        )) {
      return;
    }

    final trimmed =
        response.trim().toUpperCase();

    if (RegExp(
      r'^\d+(\.\d+)?V',
    ).hasMatch(trimmed)) {
      final voltage =
          double.tryParse(
        trimmed.replaceAll(
          'V',
          '',
        ),
      );

      if (voltage != null &&
          mounted) {
        setState(() {
          _voltage =
              voltage;
        });
      }
    }

    final pids =
        <String, void Function(int)>{
      '0C': (value) {
        _rpm = value;
      },
      '0D': (value) {
        _speed = value;
      },
      '05': (value) {
        _coolant =
            value - 40;
      },
      '11': (value) {
        _throttle =
            ((value * 100) / 255)
                .round();
      },
      '04': (value) {
        _engineLoad =
            ((value * 100) / 255)
                .round();
      },
      '0F': (value) {
        _iat =
            value - 40;
      },
      '14': (value) {
        _o2 =
            value / 200.0;
      },
    };

    for (final entry
        in pids.entries) {
      final value =
          _parsePid(
        response,
        entry.key,
      );

      if (value != null &&
          mounted) {
        setState(() {
          entry.value(
            value,
          );
        });
      }
    }

    if (clean.contains('43')) {
      _parseDtc(clean);
    }
  }

  /* ==========================================================
     DTC PARSER
     ========================================================== */

  void _parseDtc(
    String clean,
  ) {
    final index =
        clean.indexOf('43');

    if (index < 0) {
      return;
    }

    final bytes =
        clean.substring(
      index + 2,
    );

    final result =
        <String>[];

    for (
      int i = 0;
      i + 4 <= bytes.length;
      i += 4
    ) {
      final a =
          int.tryParse(
        bytes.substring(
          i,
          i + 2,
        ),
        radix: 16,
      );

      final b =
          int.tryParse(
        bytes.substring(
          i + 2,
          i + 4,
        ),
        radix: 16,
      );

      if (a == null ||
          b == null ||
          (a == 0 &&
              b == 0)) {
        continue;
      }

      final prefix =
          const [
            'P',
            'C',
            'B',
            'U',
          ][(a >> 6) & 3];

      final code =
          '$prefix'
          '${(a & 0x3F).toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}'
              .toUpperCase();

      result.add(code);
    }

    if (mounted) {
      setState(() {
        _dtcs
          ..clear()
          ..addAll(
            result.toSet(),
          );

        _loadingDtc = false;
      });
    }
  }

  /* ==========================================================
     SCAN DTC
     ========================================================== */

  Future<void> _scanDtc() async {
    if (!_connected) {
      _snack(
        'ابتدا اتصال ECU را برقرار کنید.',
      );
      return;
    }

    _pollTimer?.cancel();

    setState(() {
      _loadingDtc = true;
      _dtcs.clear();
    });

    final response =
        await _sendAndWait(
      '03',
      timeout:
          const Duration(seconds: 4),
      logCommand: true,
    );

    if (response.isEmpty &&
        mounted) {
      setState(() {
        _loadingDtc = false;
      });
    }

    _startPolling();
  }

  /* ==========================================================
     CLEAR DTC
     ========================================================== */

  Future<void> _clearDtc() async {
    if (!_connected) {
      return;
    }

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            'تأیید پاک‌سازی خطا',
          ),
          content: const Text(
            'پاک کردن DTC ممکن است '
            'مانیتورهای OBD را Reset کند. '
            'ادامه می‌دهید؟',
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
                'پاک کن',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _clearingDtc = true;
    });

    final response =
        await _sendAndWait(
      '04',
      timeout:
          const Duration(seconds: 4),
      logCommand: true,
    );

    setState(() {
      _clearingDtc = false;

      if (response.isNotEmpty &&
          !response
              .toUpperCase()
              .contains('ERROR')) {
        _dtcs.clear();
      }
    });

    _startPolling();
  }

  /* ==========================================================
     ODOMETER
     ========================================================== */

  Future<void> _readOdometer() async {
    if (!_connected) {
      return;
    }

    setState(() {
      _odometerStatus =
          'در حال استعلام...';
    });

    /*
     * 01A6 به عنوان کیلومتر واقعی
     * استفاده نمی‌شود.
     *
     * کیلومتر واقعی خودرو وابسته به ECU،
     * BCM، IPC و DID اختصاصی خودرو است.
     */

    setState(() {
      _supportsOdometer = false;

      _odometer = 0;

      _odometerStatus =
          'از ECU عمومی قابل استخراج نیست';
    });

    _log(
      'ODOMETER: generic request disabled; vehicle-specific DID required',
    );
  }

  /* ==========================================================
     ACTUATORS
     ========================================================== */

  Future<void> _runActuator(
    String name,
  ) async {
    if (!_connected) {
      _snack(
        'ابتدا ECU را متصل کنید.',
      );
      return;
    }

    /*
     * هیچ فرمان حدسی برای 2F / 30 / 31
     * یا KWP به ECU ارسال نمی‌شود.
     *
     * فرمان واقعی عملگر باید بر اساس ECU
     * دقیق، Session، Service، Identifier،
     * Positive Response و Stop Command
     * تعریف شود.
     */

    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text(name),
          content: const Text(
            'این عملگر در بانک اطلاعاتی ECU فعلی '
            'فرمان معتبر و تأییدشده ندارد.\n\n'
            'برای جلوگیری از آسیب به ECU یا خودرو، '
            'RASA هیچ فرمان حدسی 2F/30/31 ارسال نمی‌کند.\n\n'
            'پس از تعریف فرمان اختصاصی همین ECU، '
            'تست از این قسمت فعال می‌شود.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
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
  }

  /* ==========================================================
     LIVE DATA POLLING
     ========================================================== */

  void _startPolling() {
    _pollTimer?.cancel();

    if (!_connected ||
        _activeActuator
            .isNotEmpty) {
      return;
    }

    _pollIndex = 0;

    const commands = [
      '010C',
      '010D',
      '0105',
      '0111',
      '0104',
      '010F',
      '0114',
      'ATRV',
    ];

    _pollTimer =
        Timer.periodic(
      const Duration(
        milliseconds: 450,
      ),
      (_) async {
        if (!_connected ||
            _requestInFlight ||
            _activeActuator
                .isNotEmpty) {
          return;
        }

        _requestInFlight = true;

        try {
          final command =
              commands[
                  _pollIndex %
                      commands.length];

          _pollIndex++;

          await _sendAndWait(
            command,
            timeout:
                const Duration(
              milliseconds: 900,
            ),
          );
        } finally {
          _requestInFlight = false;
        }
      },
    );
  }

  /* ==========================================================
     DEMO MODE
     ========================================================== */

  void _toggleDemo(
    bool enable,
  ) {
    _demoTimer?.cancel();

    _pollTimer?.cancel();

    if (enable && _connected) {
      _disconnect();
    }

    setState(() {
      _demo = enable;
    });

    if (!enable) {
      return;
    }

    final random =
        Random();

    _demoTimer =
        Timer.periodic(
      const Duration(
        milliseconds: 300,
      ),
      (_) {
        if (!mounted) return;

        setState(() {
          _speed =
              (_speed +
                      random.nextInt(7) -
                      3)
                  .clamp(
                    0,
                    180,
                  );

          _rpm =
              (_speed * 30 +
                      850 +
                      random.nextInt(
                        250,
                      ))
                  .clamp(
                    800,
                    6500,
                  );

          _coolant =
              88 +
                  random.nextInt(
                    5,
                  );

          _throttle =
              (_speed / 2.0)
                  .round()
                  .clamp(
                    0,
                    100,
                  );

          _engineLoad =
              (15 +
                      _speed /
                          2.5)
                  .round()
                  .clamp(
                    15,
                    95,
                  );

          _iat = 30;

          _voltage =
              13.8 +
                  random.nextDouble() *
                      .3;

          _o2 =
              .35 +
                  random.nextDouble() *
                      .45;

          _ecuModel =
              'DEMO ECU';

          _protocol =
              'DEMO';
        });
      },
    );
  }

  /* ==========================================================
     DISCONNECT
     ========================================================== */

  Future<void> _disconnect() async {
    _pollTimer?.cancel();

    _pollTimer = null;

    await _serialSub?.cancel();

    _serialSub = null;

    try {
      await _connection?.finish();
    } catch (_) {}

    try {
      _connection?.dispose();
    } catch (_) {}

    _connection = null;

    if (mounted) {
      setState(() {
        _connected = false;
        _connecting = false;
        _activeActuator = '';
        _connectionStatus =
            'آماده اتصال';
      });
    }
  }

  /* ==========================================================
     SNACK
     ========================================================== */

  void _snack(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          message,
        ),
      ),
    );
  }

  /* ==========================================================
     DISPOSE
     ========================================================== */

  @override
  void dispose() {
    _demoTimer?.cancel();

    _pollTimer?.cancel();

    _serialSub?.cancel();

    _connection?.dispose();

    _tabs.dispose();

    _terminalController.dispose();

    super.dispose();
  }

  /* ==========================================================
     BUILD
     ========================================================== */

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'RASA DIAG PRO',
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            onPressed:
                _identifyVehicle,
            icon: const Icon(
              Icons.manage_search_rounded,
            ),
            tooltip:
                'شناسایی ECU',
          ),
          IconButton(
            onPressed:
                _selectBluetoothDevice,
            icon: const Icon(
              Icons.bluetooth_connected_rounded,
            ),
            tooltip:
                'اتصال',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value ==
                  'demo') {
                _toggleDemo(
                  !_demo,
                );
              }

              if (value ==
                  'disconnect') {
                _disconnect();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'demo',
                child: Text(
                  _demo
                      ? 'خاموش کردن دمو'
                      : 'حالت دمو',
                ),
              ),
              const PopupMenuItem(
                value:
                    'disconnect',
                child: Text(
                  'قطع اتصال',
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(
              icon: Icon(
                Icons.dashboard_rounded,
              ),
              text: 'داشبورد',
            ),
            Tab(
              icon: Icon(
                Icons.directions_car_rounded,
              ),
              text: 'خودرو / ECU',
            ),
            Tab(
              icon: Icon(
                Icons.sensors_rounded,
              ),
              text: 'سنسورها',
            ),
            Tab(
              icon: Icon(
                Icons.error_outline_rounded,
              ),
              text: 'خطاها',
            ),
            Tab(
              icon: Icon(
                Icons.build_circle_rounded,
              ),
              text: 'عملگرها',
            ),
            Tab(
              icon: Icon(
                Icons.memory_rounded,
              ),
              text: 'اطلاعات ECU',
            ),
            Tab(
              icon: Icon(
                Icons.terminal_rounded,
              ),
              text: 'ترمینال',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _dashboard(),
          _vehicleTab(),
          _sensorsTab(),
          _dtcTab(),
          _actuatorTab(),
          _ecuTab(),
          _terminalTab(),
        ],
      ),
    );
  }

  /* ==========================================================
     DASHBOARD
     ========================================================== */

  Widget _dashboard() {
    return ListView(
      padding:
          const EdgeInsets.all(14),
      children: [
        _statusCard(),

        const SizedBox(
          height: 12,
        ),

        Row(
          children: [
            Expanded(
              child: RasaGauge(
                label:
                    'دور موتور',
                value:
                    '$_rpm',
                unit:
                    'RPM',
                progress:
                    (_rpm / 7000)
                        .clamp(
                          0,
                          1,
                        ),
              ),
            ),

            const SizedBox(
              width: 10,
            ),

            Expanded(
              child: RasaGauge(
                label:
                    'سرعت',
                value:
                    '$_speed',
                unit:
                    'KM/H',
                progress:
                    (_speed / 240)
                        .clamp(
                          0,
                          1,
                        ),
              ),
            ),
          ],
        ),

        const SizedBox(
          height: 12,
        ),

        Row(
          children: [
            Expanded(
              child: _metric(
                'دمای آب',
                '$_coolant °C',
                Icons.thermostat,
              ),
            ),

            const SizedBox(
              width: 8,
            ),

            Expanded(
              child: _metric(
                'دریچه گاز',
                '$_throttle %',
                Icons.shutter_speed,
              ),
            ),

            const SizedBox(
              width: 8,
            ),

            Expanded(
              child: _metric(
                'ولتاژ',
                '${_voltage.toStringAsFixed(1)} V',
                Icons.bolt,
              ),
            ),
          ],
        ),

        const SizedBox(
          height: 12,
        ),

        _ecuMiniCard(),

        const SizedBox(
          height: 12,
        ),

        Card(
          child: ListTile(
            leading: const Icon(
              Icons.add_road_rounded,
              color:
                  Color(0xFF00F0FF),
            ),
            title: const Text(
              'کارکرد خودرو',
            ),
            subtitle:
                Text(
              _odometerStatus,
            ),
            trailing:
                FilledButton(
              onPressed:
                  _connected
                      ? _readOdometer
                      : null,
              child:
                  const Text(
                'استعلام',
              ),
            ),
          ),
        ),
      ],
    );
  }

  /* ==========================================================
     STATUS CARD
     ========================================================== */

  Widget _statusCard() {
    return Card(
      child: ListTile(
        leading: Icon(
          _connected
              ? Icons.check_circle
              : Icons.link_off,
          color: _connected
              ? const Color(
                  0xFF00E676,
                )
              : const Color(
                  0xFFFF2A55,
                ),
          size: 30,
        ),
        title: Text(
          _connectionStatus,
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
        subtitle: Text(
          'Protocol: $_protocol\n'
          'Adapter: $_adapterInfo',
        ),
        trailing: _demo
            ? const Chip(
                label: Text(
                  'DEMO',
                ),
              )
            : null,
      ),
    );
  }

  /* ==========================================================
     ECU MINI CARD
     ========================================================== */

  Widget _ecuMiniCard() {
    return Card(
      child: ListTile(
        leading:
            const CircleAvatar(
          backgroundColor:
              Color(0xFF18212C),
          child: Icon(
            Icons.memory_rounded,
            color:
                Color(0xFF00F0FF),
          ),
        ),
        title: const Text(
          'ECU شناسایی‌شده',
          style:
              TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
        subtitle:
            Text(_ecuModel),
        trailing:
            IconButton(
          onPressed:
              _identifyVehicle,
          icon:
              const Icon(
            Icons.refresh_rounded,
          ),
        ),
      ),
    );
  }

  /* ==========================================================
     METRIC
     ========================================================== */

  Widget _metric(
    String title,
    String value,
    IconData icon,
  ) {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          10,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color:
                  const Color(
                0xFF00F0FF,
              ),
            ),
            const SizedBox(
              height: 5,
            ),
            Text(
              title,
              style:
                  const TextStyle(
                fontSize: 10,
                color:
                    Colors.white54,
              ),
            ),
            const SizedBox(
              height: 3,
            ),
            Text(
              value,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /* ==========================================================
     VEHICLE TAB
     ========================================================== */

  Widget _vehicleTab() {
    return ListView(
      padding:
          const EdgeInsets.all(14),
      children: [
        const Text(
          'انتخاب خانواده ECU',
          style:
              TextStyle(
            fontSize: 18,
            fontWeight:
                FontWeight.bold,
          ),
        ),

        const SizedBox(
          height: 8,
        ),

        ...ecuProfiles.map(
          (profile) {
            final can =
                profile.protocol
                        .contains(
                      'CAN',
                    ) ||
                    profile.protocol
                        .contains(
                      'UDS',
                    );

            return Card(
              child: ListTile(
                leading: Icon(
                  can
                      ? Icons
                          .account_tree_rounded
                      : Icons
                          .memory_rounded,
                  color:
                      const Color(
                    0xFF00F0FF,
                  ),
                ),
                title: Text(
                  profile.title,
                ),
                subtitle: Text(
                  '${profile.family}\n'
                  '${profile.protocol}'
                  '${profile.header == null ? '' : ' • ${profile.header}'}',
                ),
                isThreeLine: true,
                trailing:
                    profile == _profile
                        ? const Icon(
                            Icons
                                .check_circle,
                            color:
                                Color(
                              0xFF00E676,
                            ),
                          )
                        : null,
                onTap: () =>
                    _applyProfile(
                  profile,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /* ==========================================================
     SENSORS TAB
     ========================================================== */

  Widget _sensorsTab() {
    return ListView(
      padding:
          const EdgeInsets.all(14),
      children: [
        _sensor(
          'RPM',
          '$_rpm RPM',
          Icons.speed,
        ),

        _sensor(
          'سرعت خودرو',
          '$_speed km/h',
          Icons.directions_car,
        ),

        _sensor(
          'دمای آب',
          '$_coolant °C',
          Icons.thermostat,
        ),

        _sensor(
          'دریچه گاز',
          '$_throttle %',
          Icons.shutter_speed,
        ),

        _sensor(
          'لود موتور',
          '$_engineLoad %',
          Icons.compress,
        ),

        _sensor(
          'دمای هوای ورودی',
          '$_iat °C',
          Icons.air,
        ),

        _sensor(
          'سنسور O2',
          '${_o2.toStringAsFixed(3)} V',
          Icons.air_rounded,
        ),

        _sensor(
          'ولتاژ سیستم',
          '${_voltage.toStringAsFixed(2)} V',
          Icons.bolt,
        ),

        _sensor(
          'کارکرد',
          _supportsOdometer
              ? '${_odometer.toStringAsFixed(0)} KM'
              : _odometerStatus,
          Icons.add_road,
        ),
      ],
    );
  }

  /* ==========================================================
     SENSOR
     ========================================================== */

  Widget _sensor(
    String name,
    String value,
    IconData icon,
  ) {
    return Card(
      child: ListTile(
        leading: Icon(
          icon,
          color:
              const Color(
            0xFF00F0FF,
          ),
        ),
        title: Text(
          name,
        ),
        trailing: Text(
          value,
          style:
              const TextStyle(
            fontWeight:
                FontWeight.bold,
            color:
                Color(
              0xFF00F0FF,
            ),
          ),
        ),
      ),
    );
  }

  /* ==========================================================
     DTC TAB
     ========================================================== */

  Widget _dtcTab() {
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.all(
            12,
          ),
          child: Row(
            children: [
              Expanded(
                child:
                    FilledButton.icon(
                  onPressed:
                      _loadingDtc
                          ? null
                          : _scanDtc,
                  icon:
                      const Icon(
                    Icons.search,
                  ),
                  label:
                      const Text(
                    'اسکن DTC',
                  ),
                ),
              ),

              const SizedBox(
                width: 10,
              ),

              Expanded(
                child:
                    FilledButton.icon(
                  onPressed:
                      _clearingDtc
                          ? null
                          : _clearDtc,
                  style:
                      FilledButton.styleFrom(
                    backgroundColor:
                        const Color(
                      0xFFFF2A55,
                    ),
                  ),
                  icon:
                      const Icon(
                    Icons.delete_sweep,
                  ),
                  label:
                      const Text(
                    'پاک‌سازی',
                  ),
                ),
              ),
            ],
          ),
        ),

        if (_loadingDtc)
          const LinearProgressIndicator(),

        Expanded(
          child: _dtcs.isEmpty
              ? const Center(
                  child: Text(
                    'خطایی در حافظه نمایش داده نشده است.',
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.all(
                    12,
                  ),
                  itemCount:
                      _dtcs.length,
                  itemBuilder:
                      (_, index) {
                    final code =
                        _dtcs[index];

                    return Card(
                      child: ListTile(
                        leading:
                            Text(
                          code,
                          style:
                              const TextStyle(
                            color:
                                Color(
                              0xFFFF2A55,
                            ),
                            fontWeight:
                                FontWeight
                                    .bold,
                          ),
                        ),
                        title: Text(
                          dtcDescriptions[
                                  code] ??
                              'شرح کارخانه‌ای / Manufacturer Specific',
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /* ==========================================================
     ACTUATOR TAB
     ========================================================== */

  Widget _actuatorTab() {
    final items = [
      'فن دور کند',
      'فن دور تند',
      'پمپ بنزین / رله دوبل',
      'شیر برقی کنیستر',
      'چراغ MIL',
    ];

    return ListView(
      padding:
          const EdgeInsets.all(14),
      children: [
        Card(
          color:
              const Color(
            0xFF17120F,
          ),
          child: const Padding(
            padding:
                EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  Icons
                      .warning_amber_rounded,
                  color:
                      Color(
                    0xFFFFD600,
                  ),
                ),
                SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: Text(
                    'عملگرها فقط با تعریف دقیق ECU، '
                    'سشن، سرویس، شناسه و پاسخ مثبت اجرا می‌شوند. '
                    'RASA فرمان حدسی ارسال نمی‌کند.',
                    style:
                        TextStyle(
                      color:
                          Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(
          height: 10,
        ),

        ...items.map(
          (name) => Card(
            child: ListTile(
              leading:
                  const Icon(
                Icons.build_circle,
                color:
                    Color(
                  0xFF00F0FF,
                ),
              ),
              title: Text(
                name,
              ),
              trailing:
                  FilledButton(
                onPressed:
                    () =>
                        _runActuator(
                  name,
                ),
                child:
                    const Text(
                  'تست',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /* ==========================================================
     ECU INFORMATION TAB
     ========================================================== */

  Widget _ecuTab() {
    return ListView(
      padding:
          const EdgeInsets.all(14),
      children: [
        Card(
          child: ListTile(
            leading:
                const Icon(
              Icons.memory,
              color:
                  Color(
                0xFF00F0FF,
              ),
              size: 32,
            ),
            title:
                const Text(
              'مدل ECU',
            ),
            subtitle:
                Text(
              _ecuModel,
              style:
                  const TextStyle(
                fontSize: 16,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            trailing:
                _scanInProgress
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(),
                      )
                    : IconButton(
                        onPressed:
                            _identifyVehicle,
                        icon:
                            const Icon(
                          Icons.refresh,
                        ),
                      ),
          ),
        ),

        _info(
          'خودرو / خانواده',
          _profile.family,
        ),

        _info(
          'پروتکل',
          _protocol,
        ),

        _info(
          'هدر CAN / KWP',
          _profile.header ??
              'Auto / Functional',
        ),

        _info(
          'VIN',
          _vin,
        ),

        _info(
          'ECU Software',
          _ecuSoftware,
        ),

        _info(
          'Adapter',
          _adapterInfo,
        ),

        const SizedBox(
          height: 10,
        ),

        FilledButton.icon(
          onPressed:
              _connected
                  ? _identifyVehicle
                  : null,
          icon:
              const Icon(
            Icons.manage_search,
          ),
          label:
              const Text(
            'شناسایی مجدد ECU',
          ),
        ),
      ],
    );
  }

  /* ==========================================================
     INFO
     ========================================================== */

  Widget _info(
    String title,
    String value,
  ) {
    return Card(
      child: ListTile(
        title: Text(
          title,
          style:
              const TextStyle(
            color:
                Colors.white54,
            fontSize: 12,
          ),
        ),
        subtitle:
            SelectableText(
          value,
          style:
              const TextStyle(
            fontSize: 14,
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /* ==========================================================
     TERMINAL
     ========================================================== */

  Widget _terminalTab() {
    return Padding(
      padding:
          const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: Card(
              child:
                  ListView.builder(
                reverse: true,
                itemCount:
                    _logs.length,
                itemBuilder:
                    (_, index) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(
                      vertical: 2,
                    ),
                    child: Text(
                      _logs[
                        _logs.length -
                            1 -
                            index
                      ],
                      style:
                          const TextStyle(
                        fontFamily:
                            'monospace',
                        fontSize: 11,
                        color:
                            Color(
                          0xFF00F0FF,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller:
                      _terminalController,
                  decoration:
                      const InputDecoration(
                    hintText:
                        '010C / 03 / ATRV / ATDP',
                  ),
                ),
              ),

              IconButton(
                onPressed: () {
                  final command =
                      _terminalController
                          .text;

                  _terminalController
                      .clear();

                  if (command
                      .isNotEmpty) {
                    _sendManual(
                      command,
                    );
                  }
                },
                icon:
                    const Icon(
                  Icons.send,
                  color:
                      Color(
                    0xFF00F0FF,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   GAUGE
   ============================================================ */

class RasaGauge
    extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final double progress;

  const RasaGauge({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.progress,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          12,
        ),
        child: Column(
          children: [
            Text(
              label,
              style:
                  const TextStyle(
                color:
                    Colors.white54,
              ),
            ),

            const SizedBox(
              height: 10,
            ),

            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment:
                    Alignment.center,
                children: [
                  CustomPaint(
                    size:
                        const Size(
                      120,
                      120,
                    ),
                    painter:
                        GaugePainter(
                      progress:
                          progress,
                    ),
                  ),

                  Column(
                    mainAxisAlignment:
                        MainAxisAlignment
                            .center,
                    children: [
                      Text(
                        value,
                        style:
                            const TextStyle(
                          fontSize: 24,
                          fontWeight:
                              FontWeight
                                  .w900,
                          color:
                              Color(
                            0xFF00F0FF,
                          ),
                        ),
                      ),
                      Text(
                        unit,
                        style:
                            const TextStyle(
                          fontSize: 10,
                          color:
                              Colors
                                  .white54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================================================
   GAUGE PAINTER
   ============================================================ */

class GaugePainter
    extends CustomPainter {
  final double progress;

  GaugePainter({
    required this.progress,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final center =
        Offset(
      size.width / 2,
      size.height / 2,
    );

    final radius =
        size.width / 2 - 8;

    final background =
        Paint()
          ..color =
              Colors.white10
          ..style =
              PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap =
              StrokeCap.round;

    final foreground =
        Paint()
          ..color =
              const Color(
            0xFF00F0FF,
          )
          ..style =
              PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap =
              StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(
        center: center,
        radius: radius,
      ),
      pi * .75,
      pi * 1.5,
      false,
      background,
    );

    canvas.drawArc(
      Rect.fromCircle(
        center: center,
        radius: radius,
      ),
      pi * .75,
      pi *
          1.5 *
          progress.clamp(
            0,
            1,
          ),
      false,
      foreground,
    );
  }

  @override
  bool shouldRepaint(
    covariant GaugePainter old,
  ) {
    return old.progress !=
        progress;
  }
}
