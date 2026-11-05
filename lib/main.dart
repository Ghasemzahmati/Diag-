import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RasaCustomization {
  final String workshopName;
  final String technicianName;
  final String phone;
  final String accentHex;
  final bool compactMode;
  const _RasaCustomization({this.workshopName = '', this.technicianName = '', this.phone = '', this.accentHex = '00F0FF', this.compactMode = false});
  Map<String, dynamic> toJson() => {'workshopName': workshopName, 'technicianName': technicianName, 'phone': phone, 'accentHex': accentHex, 'compactMode': compactMode};
  static _RasaCustomization fromJson(Map<String, dynamic> j) => _RasaCustomization(
      workshopName: '${j['workshopName'] ?? ''}',
      technicianName: '${j['technicianName'] ?? ''}',
      phone: '${j['phone'] ?? ''}',
      accentHex: '${j['accentHex'] ?? '00F0FF'}',
      compactMode: j['compactMode'] == true);
}

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
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'RASA DIAG Professional',
        // برنامه فارسی است؛ جهت راست‌به‌چپ
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox()),
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

/// هش پایدار (FNV-1a). String.hashCode در دارت بین نسخه‌ها/اجراها تضمین پایدار ندارد
/// و می‌توانست باعث باطل شدن لایسنس شود.
String _stableHash(String s) {
  var h = 0x811C9DC5;
  for (final b in utf8.encode(s)) {
    h ^= b;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).toUpperCase().padLeft(8, '0');
}

class RasaLicenseGatekeeper extends StatefulWidget {
  const RasaLicenseGatekeeper({super.key});
  @override
  State<RasaLicenseGatekeeper> createState() => _RasaLicenseGatekeeperState();
}

class _RasaLicenseGatekeeperState extends State<RasaLicenseGatekeeper> {
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
      final p = await SharedPreferences.getInstance();

      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        raw = '${a.manufacturer}-${a.model}-${a.id}'.toUpperCase();
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        raw = '${i.name}-${i.model}-${i.identifierForVendor ?? 'IOS_DEVICE'}'.toUpperCase();
      } else {
        var persistentUuid = p.getString('rasa_persistent_device_id');
        if (persistentUuid == null) {
          persistentUuid = 'RASA-DEV-${DateTime.now().millisecondsSinceEpoch}';
          await p.setString('rasa_persistent_device_id', persistentUuid);
        }
        raw = persistentUuid;
      }

      _deviceId = 'RASA-${_stableHash(raw)}';
      final local = p.getBool('license_${_deviceId.replaceAll('-', '_')}') ?? false;
      if (!mounted) return;
      setState(() => _checking = false);
      if (local) {
        _openApp();
      } else {
        await _showActivation();
      }
    } catch (_) {
      if (mounted) setState(() => _checking = false);
      await _showActivation();
    }
  }

  /// توجه: اعتبارسنجی کلید فقط طول آن را می‌سنجد؛ برای فروش واقعی باید
  /// اینجا بررسی امضا/سرور جایگزین شود.
  bool _isKeyValid(String key) => key.trim().length >= 8;

  Future<void> _showActivation() async {
    final c = TextEditingController();
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('فعال‌سازی RASA DIAG'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('شناسه دستگاه:'),
          const SizedBox(height: 8),
          SelectableText(_deviceId, style: const TextStyle(color: Color(0xFF00F0FF))),
          const SizedBox(height: 16),
          TextField(
            controller: c,
            decoration: const InputDecoration(labelText: 'کلید فعال‌سازی'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بعداً')),
          FilledButton(
            onPressed: () async {
              if (!_isKeyValid(c.text)) return;
              final p = await SharedPreferences.getInstance();
              await p.setBool('license_${_deviceId.replaceAll('-', '_')}', true);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) _openApp();
            },
            child: const Text('فعال‌سازی'),
          ),
        ],
      ),
    );
  }

  void _openApp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RasaDashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: _checking
              ? const CircularProgressIndicator()
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.car_repair_rounded, size: 72, color: Color(0xFF00F0FF)),
                  const SizedBox(height: 16),
                  const Text('RASA DIAG PROFESSIONAL', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_deviceId, style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _showActivation, child: const Text('فعال‌سازی')),
                ]),
        ),
      );
}

class ProtocolCandidate {
  final String code;
  final String command;
  final String name;
  const ProtocolCandidate(this.code, this.command, this.name);
}

const elmProtocolCandidates = <ProtocolCandidate>[
  ProtocolCandidate('0', 'ATSP0', 'AUTO'),
  ProtocolCandidate('1', 'ATSP1', 'SAE J1850 PWM 41.6 kbps'),
  ProtocolCandidate('2', 'ATSP2', 'SAE J1850 VPW 10.4 kbps'),
  ProtocolCandidate('3', 'ATSP3', 'ISO 9141-2'),
  ProtocolCandidate('4', 'ATSP4', 'ISO 14230-4 KWP 5-baud'),
  ProtocolCandidate('5', 'ATSP5', 'ISO 14230-4 KWP Fast Init'),
  ProtocolCandidate('6', 'ATSP6', 'ISO 15765-4 CAN 11-bit 500k'),
  ProtocolCandidate('7', 'ATSP7', 'ISO 15765-4 CAN 29-bit 500k'),
  ProtocolCandidate('8', 'ATSP8', 'ISO 15765-4 CAN 11-bit 250k'),
  ProtocolCandidate('9', 'ATSP9', 'ISO 15765-4 CAN 29-bit 250k'),
  ProtocolCandidate('A', 'ATSPA', 'SAE J1939 CAN 29-bit 250k'),
  ProtocolCandidate('B', 'ATSPB', 'USER CAN 1'),
  ProtocolCandidate('C', 'ATSPC', 'USER CAN 2'),
];

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

  String get title => '$manufacturer $model';
}

const ecuProfiles = <EcuProfile>[
  EcuProfile(manufacturer: 'Bosch', model: 'ME7.4.x', family: 'Peugeot / Iran Khodro', protocol: 'KWP2000', header: 'ATSH 8111F1'),
  EcuProfile(manufacturer: 'Sagem / Valeo', model: 'S2000 / PL4', family: 'Iran Khodro / Saipa', protocol: 'KWP2000', header: 'ATSH 8111F1'),
  EcuProfile(manufacturer: 'Siemens / SSAT', model: 'KWP', family: 'Iran Khodro / Saipa', protocol: 'KWP2000', header: 'ATSH 8111F1'),
  EcuProfile(manufacturer: 'Bosch', model: 'ME17 / Easy-U', family: 'Dena / Peugeot / Samand', protocol: 'CAN 500K', header: 'ATSH 7E0'),
  EcuProfile(manufacturer: 'Chery / MVM', model: 'UDS CAN', family: 'MVM / Fownix', protocol: 'UDS ISO-TP', header: 'ATSH 7E0'),
  EcuProfile(manufacturer: 'Bosch / Delphi', model: 'CAN', family: 'JAC / KMC', protocol: 'CAN 500K', header: 'ATSH 7E0'),
  EcuProfile(manufacturer: 'Haima / Changan / Brilliance', model: 'CAN', family: 'Bahman / Chinese', protocol: 'CAN 500K', header: 'ATSH 7E0'),
  EcuProfile(manufacturer: 'Generic', model: 'OBD-II', family: 'All supported vehicles', protocol: 'OBD-II', functionalHeader: 'ATSH 7DF'),
];

const dtcDescriptions = <String, String>{
  'P0100': 'مدار سنسور جریان هوای جرمی (MAF)',
  'P0105': 'مدار سنسور فشار منیفولد (MAP)',
  'P0110': 'مدار سنسور دمای هوای ورودی (IAT)',
  'P0115': 'مدار سنسور دمای مایع خنک‌کننده (ECT)',
  'P0120': 'مدار موقعیت دریچه گاز (TPS)',
  'P0130': 'مدار سنسور اکسیژن Bank 1 Sensor 1',
  'P0136': 'مدار سنسور اکسیژن Bank 1 Sensor 2',
  'P0200': 'مدار انژکتورها',
  'P0300': 'احتراق ناقص تصادفی',
  'P0335': 'سنسور موقعیت میل‌لنگ',
  'P0340': 'سنسور موقعیت میل‌سوپاپ',
  'P0420': 'راندمان کاتالیست پایین',
  'P0443': 'شیر برقی EVAP',
  'P0500': 'سنسور سرعت خودرو',
  'P0560': 'ولتاژ سیستم برق',
  'P0606': 'پردازنده ECU',
};

enum EcuConfidence { verified, partial, traceRequired }

class EcuDatabaseEntry {
  final String id;
  final String manufacturer;
  final String vehicleFamily;
  final String model;
  final String engine;
  final String ecuManufacturer;
  final String ecuModel;
  final String? hardware;
  final String? software;
  final String protocolCode;
  final String protocolName;
  final String transport;
  final String? requestHeader;
  final String? responseHeader;
  final List<String> requestHeaderCandidates;
  final List<String> responseHeaderCandidates;
  final List<int> identificationDids;
  final List<String> notes;
  final List<String> services;
  final List<String> livePids;
  final EcuConfidence confidence;
  final String sourceNote;

  const EcuDatabaseEntry({
    required this.id, required this.manufacturer, required this.vehicleFamily,
    required this.model, required this.engine, required this.ecuManufacturer,
    required this.ecuModel, this.hardware, this.software, required this.protocolCode,
    required this.protocolName, required this.transport, this.requestHeader,
    this.responseHeader, this.requestHeaderCandidates = const [],
    this.responseHeaderCandidates = const [], this.identificationDids = const [0xF190, 0xF187, 0xF188, 0xF189, 0xF191, 0xF194, 0xF195],
    this.notes = const [], this.services = const [], this.livePids = const [],
    required this.confidence, required this.sourceNote,
  });

  String get title => '$ecuManufacturer $ecuModel';
  String get confidenceText => confidence == EcuConfidence.verified ? 'تأییدشده' : confidence == EcuConfidence.partial ? 'تأیید خانواده / نیازمند Trace' : 'کاندید شناسایی؛ نیازمند Trace واقعی';
}

const rasaEcuDatabase = <EcuDatabaseEntry>[
  EcuDatabaseEntry(
    id: 'IKCO-206-TU5-ME744', manufacturer: 'Bosch', vehicleFamily: 'Iran Khodro',
    model: 'Peugeot 206 / TU5', engine: 'TU5', ecuManufacturer: 'Bosch', ecuModel: 'ME7.4.4',
    protocolCode: '5', protocolName: 'ISO 14230-4 KWP Fast Init', transport: 'K-LINE',
    services: ['KWP DTC', 'Live Data', 'Actuator Control'],
    livePids: ['RPM', 'ECT', 'TPS', 'MAP', 'IAT', 'Battery'],
    confidence: EcuConfidence.partial,
    sourceNote: 'Bosch ME7.4.4 is documented for Peugeot 206.',
  ),
  EcuDatabaseEntry(
    id: 'IKCO-DENA-EF7-ME749', manufacturer: 'Iran Khodro', vehicleFamily: 'Iran Khodro',
    model: 'Dena / EF7', engine: 'EF7', ecuManufacturer: 'Bosch', ecuModel: 'ME7.4.9',
    hardware: '0261S06345', software: '1037543902', protocolCode: '6',
    protocolName: 'ISO 15765-4 CAN 11-bit 500k', transport: 'CAN11-500',
    requestHeader: '7E0',
    services: ['OBD-II', 'UDS 2F Actuator', 'DTC', 'Odometer'],
    livePids: ['RPM', 'ECT', 'TPS', 'MAP', 'IAT', 'MAF', 'Fuel Level', 'Battery'],
    confidence: EcuConfidence.verified,
    sourceNote: 'Bosch ME7.4.9 CAN 500K with verified UDS services.',
  ),
  EcuDatabaseEntry(
    id: 'GENERIC-OBD2', manufacturer: 'Generic', vehicleFamily: 'All OBD-II vehicles',
    model: 'OBD-II', engine: 'Various', ecuManufacturer: 'Generic', ecuModel: 'OBD-II',
    protocolCode: '0', protocolName: 'AUTO', transport: 'OBD-II',
    services: ['01 Live Data', '03 DTC', '04 Clear DTC', '09 Vehicle Info'],
    livePids: ['RPM', 'Speed', 'ECT', 'Load', 'TPS', 'IAT', 'MAP', 'MAF', 'Fuel Level', 'Battery'],
    confidence: EcuConfidence.verified,
    sourceNote: 'Standard OBD-II capability.',
  ),
];

enum DiagnosticProtocol { obd, kwp, udsCan }

class OdometerDefinition {
  final String id, ecuFamily, serviceHex, didHex, unit, verification, sessionHex;
  final DiagnosticProtocol protocol;
  final int dataOffset, dataLength;
  final bool bigEndian;
  final double scale, offset;
  const OdometerDefinition({
    required this.id, required this.protocol, required this.ecuFamily,
    required this.serviceHex, required this.didHex, required this.dataLength,
    required this.verification, this.sessionHex = '', this.dataOffset = 0,
    this.bigEndian = true, this.scale = 1, this.offset = 0, this.unit = 'KM',
  });
}

const List<OdometerDefinition> verifiedOdometerDefinitions = <OdometerDefinition>[
  OdometerDefinition(
    id: 'IKCO-ME749-ODOMETER',
    protocol: DiagnosticProtocol.udsCan,
    ecuFamily: 'Dena / EF7',
    serviceHex: '22',
    didHex: '0200',
    dataOffset: 3,
    dataLength: 3,
    scale: 1.0,
    unit: 'KM',
    verification: 'تأییدشده با استاندارد Bosch ME7.4.9',
  ),
  OdometerDefinition(
    id: 'GENERIC-OBD-PID-A6',
    protocol: DiagnosticProtocol.obd,
    ecuFamily: 'All OBD-II vehicles',
    serviceHex: '01',
    didHex: 'A6',
    dataOffset: 2,
    dataLength: 4,
    scale: 0.1,
    unit: 'KM',
    verification: 'استاندارد SAE J1979 OBD-II Mode 01 PID A6',
  ),
];

enum ActuatorProtocolType { uds, kwp }

class ActuatorTestDefinition {
  final String id;
  final String name;
  final String group;
  final IconData icon;
  final ActuatorProtocolType protocol;
  final List<String> supportedEcuFamilies;
  final String startHex;
  final String stopHex;
  final int autoStopSeconds;
  final bool executionVerified;

  const ActuatorTestDefinition({
    required this.id,
    required this.name,
    required this.group,
    required this.icon,
    required this.protocol,
    required this.supportedEcuFamilies,
    required this.startHex,
    required this.stopHex,
    this.autoStopSeconds = 6,
    this.executionVerified = false,
  });
}

const List<ActuatorTestDefinition> actuatorTestCatalog = [
  ActuatorTestDefinition(
    id: 'FAN_LOW_BOSCH',
    name: 'فن خنک‌کننده (دور کند)',
    group: 'خنک‌کاری',
    icon: Icons.air_rounded,
    protocol: ActuatorProtocolType.uds,
    supportedEcuFamilies: ['IKCO-DENA-EF7-ME749'],
    startHex: '2F410A0301',
    stopHex: '2F410A00',
    autoStopSeconds: 5,
  ),
];

class IsoTpMessage {
  final List<int> payload;
  const IsoTpMessage(this.payload);
  String get hex => payload.map((e) => e.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
}

List<int> _hexBytes(String text) {
  final clean = text.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
  final out = <int>[];
  for (int i = 0; i + 1 < clean.length; i += 2) {
    final v = int.tryParse(clean.substring(i, i + 2), radix: 16);
    if (v == null) break;
    out.add(v);
  }
  return out;
}

IsoTpMessage? _isoTpReassemble(String response) {
  final lines = response
      .toUpperCase()
      .split(RegExp(r'[\r\n]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty && e != '>' && !e.contains('SEARCHING'))
      .toList();

  final frames = <List<int>>[];

  for (final line in lines) {
    final tokens = line.split(RegExp(r'\s+'));
    final hasCanId = tokens.length >= 2 && RegExp(r'^[0-9A-F]{3}$').hasMatch(tokens.first);
    final hex = hasCanId ? tokens.skip(1).join() : line.replaceAll(RegExp(r'\s+'), '');
    final bytes = _hexBytes(hex);
    if (bytes.isNotEmpty) frames.add(bytes);
  }

  if (frames.isEmpty) return null;

  final first = frames.first;
  final pci = first[0] >> 4;

  if (pci == 0) {
    final len = first[0] & 0x0F;
    if (first.length < 1 + len) return null;
    return IsoTpMessage(first.sublist(1, 1 + len));
  }

  if (pci == 1 && first.length >= 2) {
    final total = ((first[0] & 0x0F) << 8) | first[1];
    final payload = <int>[];
    payload.addAll(first.sublist(2));
    int sn = 1;

    for (final f in frames.skip(1)) {
      if (f.isEmpty) continue;
      if ((f[0] >> 4) == 3) continue;
      if ((f[0] >> 4) != 2) continue;
      if ((f[0] & 0x0F) != sn) break;

      sn = (sn + 1) & 0x0F;
      payload.addAll(f.sublist(1));

      if (payload.length >= total) {
        return IsoTpMessage(payload.sublist(0, total));
      }
    }
  }

  if (first[0] >= 0x40 && first[0] <= 0x7F) {
    return IsoTpMessage(first);
  }

  return null;
}

class RasaDashboardScreen extends StatefulWidget {
  const RasaDashboardScreen({super.key});
  @override
  State<RasaDashboardScreen> createState() => _RasaDashboardScreenState();
}

class _RasaDashboardScreenState extends State<RasaDashboardScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Socket? _connection;
  StreamSubscription<Uint8List>? _serialSub;
  Timer? _pollTimer;
  final List<String> _logs = [];
  final List<String> _dtcs = [];
  Completer<String>? _pending;
  Future<void> _commandTail = Future<void>.value();
  String _buffer = '';

  bool _connected = false;
  bool _connecting = false;
  bool _requestInFlight = false;
  bool _scanInProgress = false;
  bool _supportsOdometer = false;
  bool _obdAvailable = false;
  bool _dtcScanned = false;
  String _obdDiagnostic = 'هنوز پاسخی از ECU دریافت نشده است';
  final Set<String> _receivedPids = <String>{};

  ActuatorTestDefinition? _activeRunningTest;
  final String _lastActuatorTestResult = 'تست عملگرها در این نسخه غیرفعال است';

  EcuProfile _profile = ecuProfiles.last;
  EcuDatabaseEntry? _matchedEcu;
  String _databaseStatus = 'هنوز تطبیق ECU انجام نشده است';
  String _protocol = 'Unknown';
  String _protocolCode = '0';
  String _ecuModel = 'شناسایی نشده';
  String _vin = '---';
  String _adapterInfo = '---';
  String _connectionStatus = 'آماده اتصال';

  int _rpm = 0, _speed = 0, _coolant = 0, _throttle = 0, _engineLoad = 0;
  double _voltage = 0, _odometer = 0;
  String _odometerStatus = 'استعلام نشده';
  bool _loadingDtc = false;
  bool _clearingDtc = false;
  int _pollIndex = 0;
  final Set<String> _supportedPids = {};

  final _terminalController = TextEditingController();
  final _workshopController = TextEditingController();
  final _technicianController = TextEditingController();
  final _phoneController = TextEditingController();
  _RasaCustomization _custom = const _RasaCustomization();
  Color _accent = const Color(0xFF00F0FF);

  bool get _isCan => const ['6', '7', '8', '9'].contains(_protocolCode);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 8, vsync: this); // ۸ تب (قبلاً ۹ بود و برنامه کرش می‌کرد)
    _loadCustomization();
  }

  void _log(String s) {
    if (!mounted) return;
    setState(() {
      if (_logs.length >= 150) _logs.removeAt(0);
      _logs.add('${DateTime.now().toIso8601String().substring(11, 19)}  $s');
    });
  }

  Future<void> _selectWifiDevice() async {
    if (_connecting) return;
    final ipController = TextEditingController(text: '192.168.0.10');
    final portController = TextEditingController(text: '35000');
    final settings = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اتصال دانگل Wi-Fi OBD'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ابتدا از تنظیمات گوشی به شبکه WiFiOBD متصل شوید و گزینه «بدون اینترنت، متصل بمان» را انتخاب کنید.'),
            const SizedBox(height: 14),
            TextField(controller: ipController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'IP دانگل')),
            TextField(controller: portController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, [ipController.text.trim(), portController.text.trim()]), child: const Text('اتصال')),
        ],
      ),
    );
    if (settings == null) return;
    final ip = settings[0];
    final port = int.tryParse(settings[1]);
    if (InternetAddress.tryParse(ip) == null || port == null || port < 1 || port > 65535) {
      _snack('آدرس IP یا پورت معتبر نیست.');
      return;
    }
    await _connectWifi(ip, port);
  }

  Future<void> _connectWifi(String ip, int port) async {
    if (_connecting) return;
    await _disconnect();
    if (!mounted) return;
    setState(() {
      _connecting = true;
      _connectionStatus = 'در حال اتصال Wi-Fi به $ip:$port';
    });
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 8));
      _connection = socket;
      _serialSub = socket.listen(
        _onBytes,
        onError: (Object e) {
          _log('Wi-Fi RX ERROR $e');
          _pollTimer?.cancel();
          if (mounted) setState(() { _connected = false; _obdAvailable = false; _connectionStatus = 'خطا در ارتباط Wi-Fi'; });
        },
        onDone: () {
          _pollTimer?.cancel();
          if (mounted) setState(() { _connected = false; _obdAvailable = false; _connectionStatus = 'ارتباط Wi-Fi قطع شد'; });
        },
        cancelOnError: true,
      );
      if (!mounted) {
        socket.destroy();
        return;
      }
      setState(() {
        _connected = true;
        _connecting = false;
        _obdAvailable = false;
        _receivedPids.clear();
        _supportedPids.clear();
        _connectionStatus = 'دانگل Wi-Fi متصل؛ در حال شناسایی ECU';
      });
      _log('WIFI CONNECTED $ip:$port');
      await _initializeAdapter();
      await _identifyVehicle();
      _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _connected = false;
          _connectionStatus = 'خطا در اتصال Wi-Fi';
        });
      }
      _snack('اتصال ناموفق؛ مطمئن شوید به شبکه WiFiOBD وصل هستید: $e');
      _log('WIFI CONNECT ERROR $e');
    }
  }

  Future<void> _applyBaseSettings() async {
    for (final c in const ['ATE0', 'ATL0', 'ATS1', 'ATH1', 'ATCAF1', 'ATCFC1', 'ATAL', 'ATAT2', 'ATSTFF']) {
      await _sendAndWait(c, timeout: const Duration(seconds: 2), logCommand: true);
    }
  }

  Future<void> _initializeAdapter() async {
    await _sendAndWait('ATZ', timeout: const Duration(seconds: 6), logCommand: true);
    await Future.delayed(const Duration(milliseconds: 700));
    final ati = await _sendAndWait('ATI', timeout: const Duration(seconds: 3), logCommand: true);
    _adapterInfo = _firstUsefulLine(ati, 'ELM-compatible Wi-Fi adapter');
    await _applyBaseSettings();

    await _sendAndWait('ATSP0', timeout: const Duration(seconds: 2), logCommand: true);
    var probe = await _sendAndWait('0100', timeout: const Duration(seconds: 12), logCommand: true);
    _obdAvailable = _obdProbeSucceeded(probe);

    if (_obdAvailable) {
      await _readProtocol();
      _obdDiagnostic = 'پاسخ استاندارد OBD-II دریافت شد';
    } else {
      const likelyProtocols = <ProtocolCandidate>[
        ProtocolCandidate('5', 'ATSP5', 'ISO 14230-4 KWP Fast Init'),
        ProtocolCandidate('3', 'ATSP3', 'ISO 9141-2'),
        ProtocolCandidate('4', 'ATSP4', 'ISO 14230-4 KWP 5-baud'),
        ProtocolCandidate('6', 'ATSP6', 'ISO 15765-4 CAN 11-bit 500k'),
      ];
      for (final candidate in likelyProtocols) {
        if (!_connected) break;
        await _sendAndWait(candidate.command, timeout: const Duration(seconds: 2), logCommand: true);
        await Future.delayed(const Duration(milliseconds: 250));
        probe = await _sendAndWait('0100', timeout: const Duration(seconds: 10), logCommand: true);
        if (!_obdProbeSucceeded(probe)) {
          probe = await _sendAndWait('010C', timeout: const Duration(seconds: 7), logCommand: true);
        }
        if (_obdProbeSucceeded(probe)) {
          _protocolCode = candidate.code;
          _protocol = candidate.name;
          _obdAvailable = true;
          _obdDiagnostic = 'ECU با پروتکل ${candidate.name} پاسخ معتبر داد';
          break;
        }
      }
    }

    if (_obdAvailable) {
      await _configureProtocolTransport();
      await _discoverSupportedPids();
      if (mounted) setState(() => _connectionStatus = 'ECU پاسخ‌گو');
    } else {
      _protocol = 'پاسخ ECU دریافت نشد';
      _obdDiagnostic = 'دانگل Wi-Fi متصل است اما ECU به درخواست‌ها پاسخ نداده است.';
      if (mounted) setState(() => _connectionStatus = 'دانگل متصل؛ ارتباط ECU برقرار نشد');
    }
  }

  bool _obdProbeSucceeded(String response) {
    final clean = response.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    const signatures = ['4100', '4105', '410C', '410D', '410F', '4111', '412F'];
    return signatures.any(clean.contains);
  }

  /// شماره پروتکل را با ATDPN (دقیق) می‌خواند، نه حدس از روی متن.
  Future<void> _readProtocol() async {
    final dp = await _sendAndWait('ATDP', timeout: const Duration(seconds: 3), logCommand: true);
    final dpn = await _sendAndWait('ATDPN', timeout: const Duration(seconds: 3), logCommand: true);
    _protocol = _firstUsefulLine(dp, 'Unknown').replaceFirst(RegExp(r'^AUTO,\s*', caseSensitive: false), '');
    var code = _firstUsefulLine(dpn, '').toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (code.length == 2 && code.startsWith('A')) code = code.substring(1);
    if (RegExp(r'^[0-9A-C]$').hasMatch(code)) _protocolCode = code;
  }

  Future<void> _configureProtocolTransport() async {
    if (!_connected) return;
    if (_protocolCode == '6' || _protocolCode == '8') {
      await _sendAndWait('ATCAF1', timeout: const Duration(seconds: 1));
      await _sendAndWait('ATCFC1', timeout: const Duration(seconds: 1));
      await _sendAndWait('ATSH 7DF', timeout: const Duration(seconds: 1));
    }
  }

  String? _spCommandFor(String protocol) {
    switch (protocol) {
      case 'KWP2000':
        return 'ATSP5';
      case 'CAN 500K':
      case 'UDS ISO-TP':
        return 'ATSP6';
      default:
        return null;
    }
  }

  Future<void> _applyProfile(EcuProfile p) async {
    if (!_connected) {
      _snack('ابتدا به دانگل متصل شوید.');
      return;
    }
    _pollTimer?.cancel();
    final db = rasaEcuDatabase.where((e) => p.title.toUpperCase().contains(e.ecuModel.toUpperCase()) || p.model.toUpperCase().contains(e.ecuModel.toUpperCase())).toList();
    setState(() {
      _profile = p;
      _matchedEcu = db.isEmpty ? null : db.first;
      _databaseStatus = _matchedEcu == null ? 'پروفایل عمومی' : _matchedEcu!.title;
      _supportsOdometer = false;
      _odometer = 0;
      _odometerStatus = 'استعلام نشده';
      _connectionStatus = 'در حال اعمال پروفایل ${p.title}';
    });

    final sp = _spCommandFor(p.protocol);
    final isGeneric = sp == null;
    if (isGeneric) {
      await _sendAndWait('ATD', timeout: const Duration(seconds: 2), logCommand: true);
      await _applyBaseSettings();
      await _sendAndWait('ATSP0', timeout: const Duration(seconds: 2), logCommand: true);
    } else {
      await _sendAndWait(sp, timeout: const Duration(seconds: 2), logCommand: true);
      _protocolCode = sp.substring(4);
      _protocol = p.protocol;
      final h = p.header;
      if (h != null) await _sendAndWait(h, timeout: const Duration(seconds: 2), logCommand: true);
    }

    final probe = await _sendAndWait('0100', timeout: const Duration(seconds: 12), logCommand: true);
    _obdAvailable = _obdProbeSucceeded(probe);
    if (_obdAvailable) {
      if (isGeneric) await _readProtocol();
      _supportedPids.clear();
      await _discoverSupportedPids();
      _obdDiagnostic = 'ECU با پروفایل ${p.title} پاسخ داد';
      if (mounted) setState(() => _connectionStatus = 'ECU پاسخ‌گو');
      _startPolling();
    } else {
      _obdDiagnostic = 'ECU با پروفایل ${p.title} پاسخ نداد';
      if (mounted) setState(() => _connectionStatus = 'پاسخ ECU دریافت نشد');
      _snack('ECU با این پروفایل پاسخ نداد؛ پروفایل دیگری را امتحان کنید.');
    }
  }

  Future<void> _identifyVehicle() async {
    if (!_connected) {
      _snack('ابتدا به دانگل متصل شوید.');
      return;
    }
    if (!_obdAvailable || _scanInProgress) return;
    _pollTimer?.cancel();
    setState(() {
      _scanInProgress = true;
      _ecuModel = 'در حال شناسایی...';
      _vin = '---';
    });
    try {
      final ecuName = await _sendAndWait('090A', timeout: const Duration(seconds: 4), logCommand: true);
      final vin = await _sendAndWait('0902', timeout: const Duration(seconds: 5), logCommand: true);
      final name = _decodeInfoText(ecuName, 0x0A);
      final vinText = _decodeInfoText(vin, 0x02);
      _ecuModel = name.isNotEmpty ? name : 'توسط ECU اعلام نشد';
      _vin = vinText.isNotEmpty ? vinText : 'توسط ECU اعلام نشد';
    } catch (e) {
      _ecuModel = 'شناسایی ناموفق';
    } finally {
      if (mounted) setState(() => _scanInProgress = false);
      _startPolling();
    }
  }

  String _firstUsefulLine(String s, String fallback) {
    final lines = s.split(RegExp(r'[\r\n]+')).map((e) => e.trim()).where((e) => e.isNotEmpty && e != '>').toList();
    if (lines.isEmpty) return fallback;
    return lines.last;
  }

  /// پاسخ Mode 09 (مثل VIN و نام ECU) را رمزگشایی می‌کند. پاسخ مثبت ۴۹ است (نه ۴A).
  String _decodeInfoText(String response, int pid) {
    List<int> data = <int>[];
    if (_isCan) {
      final p = _isoTpReassemble(response)?.payload;
      if (p == null || p.length < 4 || p[0] != 0x49 || p[1] != pid) return '';
      data = p.sublist(3);
    } else {
      for (final raw in response.toUpperCase().split(RegExp(r'[\r\n]+'))) {
        final line = raw.trim();
        if (line.isEmpty || line.contains('SEARCHING')) continue;
        final b = _hexBytes(line);
        if (b.length >= 7 && b[3] == 0x49 && b[4] == pid) data.addAll(b.sublist(6, b.length - 1));
      }
    }
    final chars = data.where((c) => c >= 0x20 && c <= 0x7E).toList();
    return String.fromCharCodes(chars).trim();
  }

  /// ارسال دستور و انتظار برای پاسخ. دستورها به‌صورت صفی اجرا می‌شوند، پس همیشه
  /// حداکثر یک دستور در انتظار پاسخ است و پاسخ مستقیماً به همان تحویل می‌شود.
  Future<String> _sendAndWait(String command, {Duration timeout = const Duration(milliseconds: 1500), bool logCommand = false}) {
    final completer = Completer<String>();
    _commandTail = _commandTail.then((_) async {
      final conn = _connection;
      if (!_connected || conn == null) {
        if (!completer.isCompleted) completer.complete('');
        return;
      }
      if (logCommand) _log('TX $command');
      _buffer = ''; // پاسخ‌های دیررسیدهٔ دستور قبلی نباید با این دستور قاطی شوند
      final waiter = Completer<String>();
      _pending = waiter;
      try {
        conn.write('$command\r');
        await conn.flush();
        final result = await waiter.future.timeout(timeout, onTimeout: () => '');
        if (!completer.isCompleted) completer.complete(result);
      } catch (_) {
        if (!completer.isCompleted) completer.complete('');
      } finally {
        if (identical(_pending, waiter)) _pending = null;
      }
    }).catchError((_) {
      if (!completer.isCompleted) completer.complete('');
    });
    return completer.future;
  }

  void _onBytes(Uint8List data) {
    _buffer += utf8.decode(data, allowMalformed: true);
    while (_buffer.contains('>')) {
      final i = _buffer.indexOf('>');
      final response = _buffer.substring(0, i).trim();
      _buffer = _buffer.substring(i + 1);
      if (response.isEmpty) continue;
      _log('RX ${response.replaceAll(RegExp(r'[\r\n]+'), ' | ')}');
      final p = _pending;
      if (p != null && !p.isCompleted) p.complete(response);
      _parseResponse(response);
    }
  }

  List<int>? _parsePidBytes(String response, String pid, int count) {
    final wanted = pid.toUpperCase().padLeft(2, '0');
    for (final rawLine in response.toUpperCase().split(RegExp(r'[\r\n]+'))) {
      var line = rawLine.trim();
      if (line.isEmpty || line == '>' || line.contains('SEARCHING')) continue;
      final tokens = line.split(RegExp(r'\s+'));
      if (tokens.length > 1 && RegExp(r'^[0-9A-F]{3,8}$').hasMatch(tokens.first)) {
        line = tokens.skip(1).join();
      } else {
        line = line.replaceAll(RegExp(r'\s+'), '');
      }
      line = line.replaceAll(RegExp(r'[^0-9A-F]'), '');
      final marker = '41$wanted';
      final idx = line.indexOf(marker);
      if (idx < 0) continue;
      final dataStart = idx + marker.length;
      final dataEnd = dataStart + count * 2;
      if (dataEnd > line.length) continue;
      final bytes = <int>[];
      var valid = true;
      for (var i = dataStart; i < dataEnd; i += 2) {
        final value = int.tryParse(line.substring(i, i + 2), radix: 16);
        if (value == null) {
          valid = false;
          break;
        }
        bytes.add(value);
      }
      if (valid && bytes.length == count) return bytes;
    }
    return null;
  }

  int? _parsePid(String response, String pid) {
    final bytes = _parsePidBytes(response, pid, 1);
    return bytes == null || bytes.isEmpty ? null : bytes.first;
  }

  void _parseResponse(String response) {
    final clean = response.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    // توجه: «SEARCHING...» قبل از داده‌ی معتبر هم می‌آید و نباید پاسخ را دور بیندازد.
    if (clean.contains('NODATA') || clean.contains('ERROR') || clean.contains('UNABLETOCONNECT')) return;

    final vm = RegExp(r'^(\d+(?:\.\d+)?)V$').firstMatch(clean);
    if (vm != null) {
      final v = double.tryParse(vm.group(1)!);
      if (v != null && mounted) setState(() => _voltage = v);
    }

    final rpmBytes = _parsePidBytes(response, '0C', 2);
    if (rpmBytes != null) _receivedPids.add('0C');
    final speed = _parsePid(response, '0D');
    if (speed != null) _receivedPids.add('0D');
    final coolant = _parsePid(response, '05');
    if (coolant != null) _receivedPids.add('05');
    final throttle = _parsePid(response, '11');
    if (throttle != null) _receivedPids.add('11');
    final load = _parsePid(response, '04');
    if (load != null) _receivedPids.add('04');

    if (mounted) {
      setState(() {
        if (rpmBytes != null) _rpm = (((rpmBytes[0] << 8) | rpmBytes[1]) ~/ 4);
        if (speed != null) _speed = speed;
        if (coolant != null) _coolant = coolant - 40;
        if (throttle != null) _throttle = ((throttle * 100) / 255).round();
        if (load != null) _engineLoad = ((load * 100) / 255).round();
      });
    }
  }

  /// رمزگشایی پاسخ Mode 03 به کدهای خطا (P/C/B/U).
  List<String> _decodeDtcs(String response) {
    final codes = <String>[];
    void addPairs(List<int> bytes) {
      const letters = ['P', 'C', 'B', 'U'];
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        final a = bytes[i], b = bytes[i + 1];
        if (a == 0 && b == 0) continue;
        final code = '${letters[a >> 6]}${(a >> 4) & 0x3}${(a & 0xF).toRadixString(16)}${(b >> 4).toRadixString(16)}${(b & 0xF).toRadixString(16)}'.toUpperCase();
        if (!codes.contains(code)) codes.add(code);
      }
    }

    if (_isCan) {
      final p = _isoTpReassemble(response)?.payload;
      if (p != null && p.length >= 2 && p[0] == 0x43) addPairs(p.sublist(2));
    } else {
      for (final raw in response.toUpperCase().split(RegExp(r'[\r\n]+'))) {
        final line = raw.trim();
        if (line.isEmpty || line.contains('SEARCHING')) continue;
        final b = _hexBytes(line);
        if (b.length >= 5 && b[3] == 0x43) addPairs(b.sublist(4, b.length - 1));
      }
    }
    return codes;
  }

  Future<void> _scanDtc() async {
    if (!_connected) {
      _snack('ابتدا اتصال ECU را برقرار کنید.');
      return;
    }
    _pollTimer?.cancel();
    setState(() {
      _loadingDtc = true;
      _dtcs.clear();
    });
    try {
      final r = await _sendAndWait('03', timeout: const Duration(seconds: 6), logCommand: true);
      if (r.isEmpty) {
        _snack('پاسخی از ECU دریافت نشد.');
      } else {
        final codes = _decodeDtcs(r);
        if (mounted) {
          setState(() {
            _dtcs.addAll(codes);
            _dtcScanned = true;
          });
        }
      }
    } finally {
      if (mounted) setState(() => _loadingDtc = false);
      _startPolling();
    }
  }

  Future<void> _clearDtc() async {
    if (!_connected) {
      _snack('ابتدا اتصال ECU را برقرار کنید.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('پاک‌سازی خطاها'),
        content: const Text('با پاک‌سازی خطاها، اطلاعات Freeze Frame و وضعیت آمادگی مانیتورها (Readiness) نیز ریست می‌شود. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('پاک‌سازی')),
        ],
      ),
    );
    if (ok != true) return;
    _pollTimer?.cancel();
    setState(() => _clearingDtc = true);
    try {
      final r = await _sendAndWait('04', timeout: const Duration(seconds: 5), logCommand: true);
      final clean = r.replaceAll(RegExp(r'\s+'), '').toUpperCase();
      if (clean.contains('44')) {
        if (mounted) setState(() => _dtcs.clear());
        _snack('خطاها پاک شد.');
      } else {
        _snack('ECU پاک‌سازی را تأیید نکرد (ممکن است موتور روشن باشد).');
      }
    } finally {
      if (mounted) setState(() => _clearingDtc = false);
      _startPolling();
    }
  }

  Future<void> _readOdometer() async {
    if (!_connected) {
      _snack('ابتدا اتصال به دانگل را برقرار کنید.');
      return;
    }
    setState(() => _odometerStatus = 'در حال استعلام کارکرد...');
    try {
      final obdResp = await _sendAndWait('01A6', timeout: const Duration(seconds: 3), logCommand: true);
      final obdBytes = _parsePidBytes(obdResp, 'A6', 4);
      if (obdBytes != null && obdBytes.length == 4) {
        final rawVal = ((obdBytes[0] << 24) | (obdBytes[1] << 16) | (obdBytes[2] << 8) | obdBytes[3]);
        final km = rawVal / 10.0;
        if (!mounted) return;
        setState(() {
          _supportsOdometer = true;
          _odometer = km;
          _odometerStatus = '${km.toStringAsFixed(0)} KM';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _supportsOdometer = false;
        _odometerStatus = 'پشتیبانی نمی‌شود';
      });
    } catch (e) {
      if (mounted) setState(() => _odometerStatus = 'خطا در خواندن');
    }
  }

  Future<void> _discoverSupportedPids() async {
    if (!_connected || !_obdAvailable) return;
    final found = <String>{};
    for (final pid in const ['00', '20', '40']) {
      if (pid != '00' && !found.contains(pid)) break; // بازه بعدی فقط وقتی پشتیبانی شود که ECU اعلام کرده باشد
      final r = await _sendAndWait('01$pid', timeout: const Duration(seconds: 4));
      final clean = r.replaceAll(RegExp(r'\s+'), '').toUpperCase();
      final marker = '41$pid';
      final idx = clean.indexOf(marker);
      if (idx >= 0 && idx + 12 <= clean.length) {
        final bits = int.tryParse(clean.substring(idx + 4, idx + 12), radix: 16);
        if (bits != null) {
          for (var b = 0; b < 32; b++) {
            if ((bits & (1 << (31 - b))) != 0) {
              final p = int.parse(pid, radix: 16) + b + 1;
              found.add(p.toRadixString(16).padLeft(2, '0').toUpperCase());
            }
          }
        }
      }
    }
    _supportedPids
      ..clear()
      ..addAll(found);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (!_connected || !_obdAvailable) return;
    const base = ['0C', '0D', '05', '0C', '11', '04', '0C', 'ATRV'];
    final cmds = base.where((c) => c == 'ATRV' || _supportedPids.isEmpty || _supportedPids.contains(c)).toList();
    if (cmds.isEmpty) return;
    _pollIndex = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      if (!_connected || _requestInFlight || _activeRunningTest != null) return;
      _requestInFlight = true;
      try {
        final c = cmds[_pollIndex % cmds.length];
        _pollIndex++;
        await _sendAndWait(c == 'ATRV' ? c : '01$c', timeout: const Duration(seconds: 3));
      } finally {
        _requestInFlight = false;
      }
    });
  }

  Future<void> _disconnect() async {
    _activeRunningTest = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    final p = _pending;
    if (p != null && !p.isCompleted) p.complete('');
    _pending = null;
    _buffer = '';
    await _serialSub?.cancel();
    _serialSub = null;
    try { _connection?.destroy(); } catch (_) {}
    _connection = null;
    if (mounted) {
      setState(() {
        _connected = false;
        _connecting = false;
        _obdAvailable = false;
        _connectionStatus = 'آماده اتصال';
      });
    }
  }

  void _snack(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _serialSub?.cancel();
    _connection?.destroy();
    _tabs.dispose();
    _terminalController.dispose();
    _workshopController.dispose();
    _technicianController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomization() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('rasa_customization');
    if (raw != null) {
      try { _custom = _RasaCustomization.fromJson(jsonDecode(raw)); } catch (_) {}
    }
    _workshopController.text = _custom.workshopName;
    _technicianController.text = _custom.technicianName;
    _phoneController.text = _custom.phone;
    try { _accent = Color(int.parse('FF${_custom.accentHex}', radix: 16)); } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _saveCustomization() async {
    final c = _RasaCustomization(
      workshopName: _workshopController.text.trim(),
      technicianName: _technicianController.text.trim(),
      phone: _phoneController.text.trim(),
      accentHex: _custom.accentHex,
      compactMode: _custom.compactMode,
    );
    final p = await SharedPreferences.getInstance();
    await p.setString('rasa_customization', jsonEncode(c.toJson()));
    _custom = c;
    if (mounted) setState(() {});
    _snack('شخصی‌سازی ذخیره شد');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_custom.workshopName.isEmpty ? 'RASA DIAG PRO' : _custom.workshopName, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(onPressed: _identifyVehicle, icon: const Icon(Icons.manage_search_rounded), tooltip: 'شناسایی ECU'),
          IconButton(onPressed: _selectWifiDevice, icon: const Icon(Icons.wifi_tethering_rounded), tooltip: 'اتصال دانگل Wi-Fi'),
          IconButton(onPressed: _disconnect, icon: const Icon(Icons.link_off_rounded), tooltip: 'قطع ارتباط'),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_rounded), text: 'داشبورد'),
            Tab(icon: Icon(Icons.directions_car_rounded), text: 'خودرو / ECU'),
            Tab(icon: Icon(Icons.sensors_rounded), text: 'سنسورها'),
            Tab(icon: Icon(Icons.error_outline_rounded), text: 'خطاها'),
            Tab(icon: Icon(Icons.build_circle_rounded), text: 'عملگرها'),
            Tab(icon: Icon(Icons.memory_rounded), text: 'اطلاعات ECU'),
            Tab(icon: Icon(Icons.terminal_rounded), text: 'ترمینال'),
            Tab(icon: Icon(Icons.tune_rounded), text: 'شخصی‌سازی'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _dashboard(), _vehicleTab(), _sensorsTab(), _dtcTab(), _actuatorTab(), _ecuTab(), _terminalTab(), _customTab(),
      ]),
    );
  }

  Widget _dashboard() => ListView(padding: const EdgeInsets.all(14), children: [
        _statusCard(),
        if (!_connected) ...[
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _connecting ? null : _selectWifiDevice, icon: const Icon(Icons.wifi_tethering_rounded), label: const Text('اتصال دانگل Wi-Fi')),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: RasaGauge(label: 'دور موتور', value: '$_rpm', unit: 'RPM', progress: (_rpm / 7000).clamp(0.0, 1.0).toDouble(), color: _accent)),
          const SizedBox(width: 10),
          Expanded(child: RasaGauge(label: 'سرعت', value: '$_speed', unit: 'KM/H', progress: (_speed / 240).clamp(0.0, 1.0).toDouble(), color: _accent)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _metric('دمای آب', '$_coolant °C', Icons.thermostat)),
          const SizedBox(width: 8), Expanded(child: _metric('دریچه گاز', '$_throttle %', Icons.shutter_speed)),
          const SizedBox(width: 8), Expanded(child: _metric('ولتاژ', '${_voltage.toStringAsFixed(1)} V', Icons.bolt)),
        ]),
      ]);

  Widget _statusCard() => Card(
        child: ListTile(
          leading: Icon(_connected ? Icons.check_circle : Icons.link_off, color: _connected ? const Color(0xFF00E676) : const Color(0xFFFF2A55), size: 30),
          title: Text(_connectionStatus, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('Protocol: $_protocol\nAdapter: $_adapterInfo'),
        ),
      );

  Widget _metric(String title, String value, IconData icon) => Card(
      child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            Icon(icon, color: _accent),
            const SizedBox(height: 5),
            Text(title, style: const TextStyle(fontSize: 10, color: Colors.white54)),
            const SizedBox(height: 3),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ])));

  Widget _vehicleTab() => ListView(padding: const EdgeInsets.all(14), children: [
        ...ecuProfiles.map((p) => Card(
              shape: p == _profile ? RoundedRectangleBorder(side: BorderSide(color: _accent), borderRadius: BorderRadius.circular(12)) : null,
              child: ListTile(
                leading: Icon(Icons.memory_rounded, color: _accent),
                title: Text(p.title),
                subtitle: Text('${p.family}\n${p.protocol}'),
                onTap: () => _applyProfile(p),
              ),
            )),
      ]);

  Widget _sensorsTab() => ListView(padding: const EdgeInsets.all(14), children: [
        _sensor('RPM', '$_rpm RPM', Icons.speed),
        _sensor('سرعت', '$_speed km/h', Icons.directions_car),
        _sensor('دمای آب', '$_coolant °C', Icons.thermostat),
        _sensor('دریچه گاز', '$_throttle %', Icons.shutter_speed),
        _sensor('بار موتور', '$_engineLoad %', Icons.engineering),
        _sensor('ولتاژ سیستم', '${_voltage.toStringAsFixed(2)} V', Icons.bolt),
      ]);

  Widget _sensor(String n, String v, IconData i) => Card(
          child: ListTile(
        leading: Icon(i, color: _accent),
        title: Text(n),
        subtitle: Text(v, style: TextStyle(fontWeight: FontWeight.bold, color: _accent)),
      ));

  Widget _dtcTab() => Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(child: FilledButton.icon(onPressed: _loadingDtc ? null : _scanDtc, icon: const Icon(Icons.search), label: const Text('اسکن DTC'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton.icon(onPressed: _clearingDtc ? null : _clearDtc, style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF2A55)), icon: const Icon(Icons.delete_sweep), label: const Text('پاک‌سازی'))),
            ])),
        if (_loadingDtc) const LinearProgressIndicator(),
        Expanded(
            child: _dtcs.isEmpty
                ? Center(child: Text(_dtcScanned ? 'خطایی یافت نشد.' : 'برای خواندن خطاها «اسکن DTC» را بزنید.'))
                : ListView.builder(
                    itemCount: _dtcs.length,
                    itemBuilder: (_, i) {
                      final c = _dtcs[i];
                      return Card(child: ListTile(leading: Text(c, style: const TextStyle(color: Color(0xFFFF2A55), fontWeight: FontWeight.bold)), title: Text(dtcDescriptions[c] ?? 'خطای ناشناخته')));
                    })),
      ]);

  Widget _actuatorTab() => ListView(padding: const EdgeInsets.all(14), children: [
        Card(child: ListTile(title: const Text('تست عملگرها'), subtitle: Text(_lastActuatorTestResult))),
      ]);

  Widget _ecuTab() => ListView(padding: const EdgeInsets.all(14), children: [
        _info('مدل ECU', _ecuModel),
        _info('VIN', _vin),
        _info('پروتکل', _protocol),
        _info('آداپتور', _adapterInfo),
        _info('پروفایل / پایگاه داده', _databaseStatus),
        _info('وضعیت ارتباط', _obdDiagnostic),
        _info('کارکرد (Odometer)', _odometerStatus),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: _readOdometer, icon: const Icon(Icons.speed), label: const Text('خواندن کارکرد')),
      ]);

  Widget _info(String a, String b) => Card(child: ListTile(title: Text(a, style: const TextStyle(color: Colors.white54, fontSize: 12)), subtitle: SelectableText(b, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))));

  Widget _terminalTab() => Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Expanded(
            child: Card(
                child: ListView.builder(
                    reverse: true,
                    itemCount: _logs.length,
                    itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(_logs[_logs.length - 1 - i], textDirection: TextDirection.ltr, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: _accent)))))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _terminalController, textDirection: TextDirection.ltr, decoration: const InputDecoration(hintText: '010C / 03 / ATRV'))),
          IconButton(
              onPressed: () {
                final c = _terminalController.text.trim();
                _terminalController.clear();
                if (c.isEmpty) return;
                if (!_connected) {
                  _snack('ابتدا به دانگل متصل شوید.');
                  return;
                }
                _sendAndWait(c, timeout: const Duration(seconds: 5), logCommand: true);
              },
              icon: Icon(Icons.send, color: _accent)),
        ]),
      ]));

  Widget _customTab() => ListView(padding: const EdgeInsets.all(14), children: [
        Card(
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('شخصی‌سازی حرفه‌ای', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  TextField(controller: _workshopController, decoration: const InputDecoration(labelText: 'نام تعمیرگاه')),
                  const SizedBox(height: 8),
                  TextField(controller: _technicianController, decoration: const InputDecoration(labelText: 'نام تکنسین')),
                  const SizedBox(height: 8),
                  TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'شماره تماس')),
                  const SizedBox(height: 14),
                  FilledButton.icon(onPressed: _saveCustomization, icon: const Icon(Icons.save), label: const Text('ذخیره شخصی‌سازی')),
                ]))),
      ]);
}

class RasaGauge extends StatelessWidget {
  final String label, value, unit;
  final double progress;
  final Color color;
  const RasaGauge({super.key, required this.label, required this.value, required this.unit, required this.progress, this.color = const Color(0xFF00F0FF)});
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Text(label, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 10),
            SizedBox(
                width: 120,
                height: 120,
                child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(size: const Size(120, 120), painter: GaugePainter(progress: progress, color: color)),
                  Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
                    Text(unit, style: const TextStyle(fontSize: 10, color: Colors.white54)),
                  ]),
                ])),
          ])));
}

class GaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  GaugePainter({required this.progress, this.color = const Color(0xFF00F0FF)});
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2), r = size.width / 2 - 8;
    final bg = Paint()..color = Colors.white10..style = PaintingStyle.stroke..strokeWidth = 9..strokeCap = StrokeCap.round;
    final fg = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 9..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), pi * .75, pi * 1.5, false, bg);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), pi * .75, pi * 1.5 * progress.clamp(0.0, 1.0).toDouble(), false, fg);
  }
  @override
  bool shouldRepaint(covariant GaugePainter old) => old.progress != progress || old.color != color;
}
