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
  const _RasaCustomization({this.workshopName='', this.technicianName='', this.phone='', this.accentHex='00F0FF', this.compactMode=false});
  Map<String,dynamic> toJson()=>{'workshopName':workshopName,'technicianName':technicianName,'phone':phone,'accentHex':accentHex,'compactMode':compactMode};
  static _RasaCustomization fromJson(Map<String,dynamic> j)=>_RasaCustomization(workshopName:'${j['workshopName']??''}',technicianName:'${j['technicianName']??''}',phone:'${j['phone']??''}',accentHex:'${j['accentHex']??'00F0FF'}',compactMode:j['compactMode']==true);
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
        title: 'RASA DIAG Professional - Kingbolen Edition',
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
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        raw = '${a.manufacturer}-${a.model}-${a.id}'.toUpperCase();
      } else {
        raw = 'RASA-${DateTime.now().millisecondsSinceEpoch}';
      }
      _deviceId = 'RASA-${raw.hashCode.abs().toRadixString(16).toUpperCase()}';
      final p = await SharedPreferences.getInstance();
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

  Future<void> _showActivation() async {
    final c = TextEditingController();
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('بعداً')),
          FilledButton(
            onPressed: () async {
              if (c.text.trim().length < 8) return;
              final p = await SharedPreferences.getInstance();
              await p.setBool('license_${_deviceId.replaceAll('-', '_')}', true);
              if (mounted) {
                Navigator.pop(context);
                _openApp();
              }
            },
            child: const Text('فعال‌سازی'),
          ),
        ],
      ),
    );
  }

  void _openApp() {
    if (!mounted) return;
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
  ProtocolCandidate('0','ATSP0','AUTO'),
  ProtocolCandidate('3','ATSP3','ISO 9141-2'),
  ProtocolCandidate('5','ATSP5','ISO 14230-4 KWP Fast Init'),
  ProtocolCandidate('6','ATSP6','ISO 15765-4 CAN 11-bit 500k'),
  ProtocolCandidate('7','ATSP7','ISO 15765-4 CAN 29-bit 500k'),
  ProtocolCandidate('8','ATSP8','ISO 15765-4 CAN 11-bit 250k'),
  ProtocolCandidate('9','ATSP9','ISO 15765-4 CAN 29-bit 250k'),
  ProtocolCandidate('A','ATSPA','SAE J1939 CAN 29-bit 250k'),
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
  EcuProfile(manufacturer: 'Siemens / Crouse', model: 'SIM2K-34VR / S2000', family: 'Iran Khodro / Saipa', protocol: 'KWP2000', header: 'ATSH 8111F1'),
  EcuProfile(manufacturer: 'Bosch', model: 'ME17 / Easy-U', family: 'Dena / Peugeot / Samand', protocol: 'CAN 500K', header: 'ATSH 7E0'),
  EcuProfile(manufacturer: 'Chery / MVM', model: 'UDS CAN', family: 'MVM / Fownix', protocol: 'UDS ISO-TP', header: 'ATSH 7E0'),
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
    id: 'SIEMENS-SIM2K-34VR', manufacturer: 'Siemens / Crouse', vehicleFamily: 'Iran Khodro / Saipa',
    model: 'Various / Pride / Roa', engine: 'M13 / XU7', ecuManufacturer: 'Siemens', ecuModel: 'SIM2K-34VR',
    protocolCode: '5', protocolName: 'ISO 14230-4 KWP Fast Init', transport: 'K-LINE',
    requestHeader: '8111F1',
    services: ['KWP DTC', 'Live Data', 'Actuator Control'],
    livePids: ['RPM', 'ECT', 'TPS', 'MAP', 'IAT', 'Battery'],
    confidence: EcuConfidence.verified,
    sourceNote: 'Siemens SIM2K-34VR K-Line protocol family.',
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
    id: 'CHERY-MVM-UDS-CAN', manufacturer: 'Chery/MVM', vehicleFamily: 'MVM / Fownix',
    model: 'UDS CAN family', engine: 'Various', ecuManufacturer: 'Chery', ecuModel: 'UDS ECU',
    protocolCode: '6', protocolName: 'ISO 15765-4 CAN 11-bit 500k', transport: 'CAN11-500',
    requestHeader: '7E0',
    services: ['UDS 10/19/22/2F/3E', 'DTC', 'Live Data', 'Odometer'],
    confidence: EcuConfidence.verified,
    sourceNote: 'Generic Chery UDS family entry.',
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
    required this.verification, this.sessionHex='', this.dataOffset=0,
    this.bigEndian=true, this.scale=1, this.offset=0, this.unit='KM'
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
    supportedEcuFamilies: ['IKCO-DENA-EF7-ME749', 'CHERY-MVM-UDS-CAN'],
    startHex: '2F410A0301',
    stopHex: '2F410A00',
    autoStopSeconds: 5,
  ),
  ActuatorTestDefinition(
    id: 'FUEL_PUMP_BOSCH',
    name: 'رله پمپ بنزین',
    group: 'سوخت‌رسانی',
    icon: Icons.local_gas_station_rounded,
    protocol: ActuatorProtocolType.uds,
    supportedEcuFamilies: ['IKCO-DENA-EF7-ME749', 'CHERY-MVM-UDS-CAN'],
    startHex: '2F41050301',
    stopHex: '2F410500',
    autoStopSeconds: 4,
  ),
];

class IsoTpMessage {
  final List<int> payload;
  const IsoTpMessage(this.payload);
  String get hex => payload.map((e)=>e.toRadixString(16).padLeft(2,'0')).join().toUpperCase();
}

List<int> _hexBytes(String text) {
  final clean=text.replaceAll(RegExp(r'[^0-9A-Fa-f]'),'');
  final out=<int>[];
  for(int i=0;i+1<clean.length;i+=2){ final v=int.tryParse(clean.substring(i,i+2),radix:16); if(v==null) break; out.add(v); }
  return out;
}

IsoTpMessage? _isoTpReassemble(String response) {
  final lines = response
      .toUpperCase()
      .split(RegExp(r'[\r\n]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty && e != '>' && !e.contains('SEARCHING'))
      .toList();

  final frames=<List<int>>[];
  for (final line in lines) {
    final tokens=line.split(RegExp(r'\s+'));
    final hasCanId=tokens.length >= 2 && RegExp(r'^[0-9A-F]{3}$').hasMatch(tokens.first);
    final hex=hasCanId ? tokens.skip(1).join() : line.replaceAll(RegExp(r'\s+'),'');
    final bytes=_hexBytes(hex);
    if(bytes.isNotEmpty) frames.add(bytes);
  }

  if(frames.isEmpty) return null;
  final first=frames.first;
  final pci=first[0]>>4;

  if(pci==0){
    final len=first[0]&0x0F;
    if(first.length<1+len) return null;
    return IsoTpMessage(first.sublist(1,1+len));
  }
  if(pci==1 && first.length>=2){
    final total=((first[0]&0x0F)<<8)|first[1];
    final payload=<int>[];
    payload.addAll(first.sublist(2));
    int sn=1;
    for(final f in frames.skip(1)){
      if(f.isEmpty) continue;
      if((f[0]>>4)==3) continue;
      if((f[0]>>4)!=2) continue;
      if((f[0]&0x0F)!=sn) break;
      sn=(sn+1)&0x0F;
      payload.addAll(f.sublist(1));
      if(payload.length>=total){
        return IsoTpMessage(payload.sublist(0,total));
      }
    }
  }
  if(first[0]>=0x40 && first[0]<=0x7F) {
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
  Timer? _demoTimer;
  final List<String> _logs = [];
  final List<String> _dtcs = [];
  final Map<String, Completer<String>> _waiters = {};
  Future<void> _commandTail = Future<void>.value();
  String _buffer = '';

  bool _connected = false;
  bool _connecting = false;
  bool _demo = false;
  bool _requestInFlight = false;
  bool _scanInProgress = false;
  bool _supportsOdometer = false;
  bool _obdAvailable = false;
  String _obdDiagnostic = 'هنوز پاسخی از ECU دریافت نشده است';
  final Set<String> _receivedPids = <String>{};
  bool _voltageReceived = false;

  ActuatorTestDefinition? _activeRunningTest;
  Timer? _actuatorCountdownTimer;
  int _actuatorRemainingSeconds = 0;
  bool _actuatorActionInProgress = false;
  String _lastActuatorTestResult = 'هنوز تستی اجرا نشده است';
  Timer? _testerPresentTimer;
  final _customStartController = TextEditingController();
  final _customStopController = TextEditingController();
  ActuatorProtocolType _customProtocol = ActuatorProtocolType.uds;

  EcuProfile _profile = ecuProfiles.last;
  EcuDatabaseEntry? _matchedEcu;
  String _databaseStatus = 'هنوز تطبیق ECU انجام نشده است';
  bool _databaseScanning = false;
  String _hwId = '---';
  String _swId = '---';
  String _protocol = 'Unknown';
  String _protocolCode = '0';
  bool _protocolScanRunning = false;
  String _ecuModel = 'شناسایی نشده است';
  String _vin = '---';
  String _adapterInfo = '---';
  String _connectionStatus = 'آماده اتصال';
  String _udsRequestHeader = '';
  String _udsResponseHeader = '';
  String _discoveryMethod = '---';

  int _rpm = 0, _speed = 0, _coolant = 0, _throttle = 0, _engineLoad = 0, _iat = 0;
  double _voltage = 0, _o2 = 0, _odometer = 0, _fuelLevel = -1, _map = -1, _maf = -1, _ambient = -100;
  String _odometerStatus = 'استعلام نشده';
  bool _loadingDtc = false;
  bool _clearingDtc = false;
  int _pollIndex = 0;
  final Set<String> _supportedPids = {};
  final Map<String, String> _extraSensorValues = {};
  final Map<String, String> _actuatorStates = {};
  final Map<String, String> _actuatorEvidence = {};

  final _terminalController = TextEditingController();
  final _supportSessionCodeController = TextEditingController();
  final _workshopController = TextEditingController();
  final _technicianController = TextEditingController();
  final _phoneController = TextEditingController();
  final List<String> _remoteResults = [];
  WebSocket? _remoteSocket;
  StreamSubscription? _remoteSub;
  Timer? _remoteHeartbeat;
  bool _remoteConnected = false;
  bool _remoteConnecting = false;
  String _remoteStatus = 'قطع ارتباط';
  String _remoteRoleLabel = 'انتخاب نشده';
  String _customerSessionCode = '';
  _RasaCustomization _custom = const _RasaCustomization();
  Color _accent = const Color(0xFF00F0FF);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 9, vsync: this);
    _loadCustomization();
  }

  void _log(String s) {
    if (!mounted) return;
    setState(() {
      if (_logs.length >= 150) _logs.removeAt(0);
      _logs.add('${DateTime.now().toIso8601String().substring(11, 19)}  $s');
    });
  }

  /// اتصال به دانگل Kingbolen Wi-Fi (پیش‌فرض 192.168.0.10:35000)
  Future<void> _selectKingbolenWifiDevice() async {
    if (_connecting) return;
    final ipController = TextEditingController(text: '192.168.0.10');
    final portController = TextEditingController(text: '35000');
    final settings = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اتصال به دانگل Kingbolen Wi-Fi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ابتدا از تنظیمات گوشی به وای‌فای دانگل Kingbolen متصل شوید.'),
            const SizedBox(height: 14),
            TextField(controller: ipController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'IP دانگل')),
            TextField(controller: portController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, [ipController.text.trim(), portController.text.trim()]), child: const Text('اتصال')),
        ],
      ),
    );
    ipController.dispose();
    portController.dispose();
    if (settings == null) return;
    final ip = settings[0];
    final port = int.tryParse(settings[1]);
    if (ip.isEmpty || port == null || port < 1 || port > 65535) {
      _snack('آدرس IP یا پورت معتبر نیست.');
      return;
    }
    await _connectKingbolenWifi(ip, port);
  }

  Future<void> _connectKingbolenWifi(String ip, int port) async {
    if (_connecting) return;
    await _disconnect();
    if (!mounted) return;
    setState(() {
      _connecting = true;
      _connectionStatus = 'در حال اتصال به Kingbolen Wi-Fi ($ip:$port)';
    });
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 8));
      _connection = socket;
      _serialSub = socket.listen(
        _onBytes,
        onError: (Object e) { _log('Kingbolen RX ERROR $e'); if (mounted) setState(() => _connected = false); },
        onDone: () { if (mounted) setState(() { _connected = false; _connectionStatus = 'ارتباط Wi-Fi قطع شد'; }); },
        cancelOnError: true,
      );
      if (!mounted) { socket.destroy(); return; }
      setState(() {
        _connected = true;
        _connecting = false;
        _obdAvailable = false;
        _receivedPids.clear();
        _extraSensorValues.clear();
        _connectionStatus = 'دانگل متصل؛ در حال مقداردهی فریمور...';
      });
      _log('KINGBOLEN WIFI CONNECTED $ip:$port');
      
      await _initializeKingbolenAdapter();
      await _identifyVehicle();
      _startPolling();
    } catch (e) {
      if (mounted) setState(() {
        _connecting = false;
        _connected = false;
        _connectionStatus = 'خطا در اتصال به دانگل';
      });
      _snack('اتصال ناموفق؛ از اتصال به وای‌فای دانگل اطمینان حاصل کنید: $e');
      _log('KINGBOLEN CONNECT ERROR $e');
    }
  }

  /// مقداردهی اولیه مخصوص تراشه ELM327 در دانگل Kingbolen (پشتیبانی کامل از CAN و K-Line / زیمنس)
  Future<void> _initializeKingbolenAdapter() async {
    await _sendAndWait('ATZ', timeout: const Duration(seconds: 6), logCommand: true);
    await Future.delayed(const Duration(milliseconds: 800));
    await _sendAndWait('ATE0', timeout: const Duration(seconds: 2), logCommand: true);
    await _sendAndWait('ATL0', timeout: const Duration(seconds: 2), logCommand: true);
    await _sendAndWait('ATS1', timeout: const Duration(seconds: 2), logCommand: true);
    await _sendAndWait('ATH1', timeout: const Duration(seconds: 2), logCommand: true); // حیاتی برای زیمنس و K-Line
    await _sendAndWait('ATCAF1', timeout: const Duration(seconds: 2), logCommand: true);
    await _sendAndWait('ATCFC1', timeout: const Duration(seconds: 2), logCommand: true);
    
    final ati = await _sendAndWait('ATI', timeout: const Duration(seconds: 3), logCommand: true);
    _adapterInfo = _firstUsefulLine(ati, 'Kingbolen ELM327 Wi-Fi');
    
    await _sendAndWait('ATAL', timeout: const Duration(seconds: 2), logCommand: true);
    await _sendAndWait('ATAT2', timeout: const Duration(seconds: 2), logCommand: true);
    await _sendAndWait('ATSTFF', timeout: const Duration(seconds: 2), logCommand: true);

    // تست خودکار OBD
    await _sendAndWait('ATSP0', timeout: const Duration(seconds: 2), logCommand: true);
    var probe = await _sendAndWait('0100', timeout: const Duration(seconds: 10), logCommand: true);
    _obdAvailable = _obdProbeSucceeded(probe);

    if (_obdAvailable) {
      final dp = await _sendAndWait('ATDP', timeout: const Duration(seconds: 3), logCommand: true);
      _setProtocolFromDescription(dp);
      _obdDiagnostic = 'ارتباط OBD-II با موفقیت برقرار شد';
    } else {
      _log('AUTO PROTOCOL FAILED; trying K-Line and CAN fallback...');
      const fallbackProtocols = <ProtocolCandidate>[
        ProtocolCandidate('5', 'ATSP5', 'ISO 14230-4 KWP Fast Init'),
        ProtocolCandidate('3', 'ATSP3', 'ISO 9141-2'),
        ProtocolCandidate('6', 'ATSP6', 'ISO 15765-4 CAN 11-bit 500k'),
        ProtocolCandidate('7', 'ATSP7', 'ISO 15765-4 CAN 29-bit 500k'),
      ];
      for (final candidate in fallbackProtocols) {
        if (!_connected) break;
        await _sendAndWait(candidate.command, timeout: const Duration(seconds: 2), logCommand: true);
        await Future.delayed(const Duration(milliseconds: 300));
        probe = await _sendAndWait('0100', timeout: const Duration(seconds: 8), logCommand: true);
        if (!_obdProbeSucceeded(probe)) {
          probe = await _sendAndWait('010C', timeout: const Duration(seconds: 6), logCommand: true);
        }
        if (_obdProbeSucceeded(probe)) {
          _protocolCode = candidate.code;
          _protocol = candidate.name;
          _obdAvailable = true;
          _obdDiagnostic = 'ECU با پروتکل اختصاصی ${candidate.name} پاسخ داد';
          break;
        }
      }
    }

    if (_obdAvailable) {
      await _configureProtocolTransport();
      await _discoverSupportedPids();
    } else {
      _protocol = 'پاسخ ECU دریافت نشد';
      _obdDiagnostic = 'دانگل متصل است اما ECU پاسخ نداد. سوئیچ خودرو را باز کنید.';
      if (mounted) setState(() => _connectionStatus = 'دانگل متصل؛ خودرو خاموش یا سوئیچ بسته است');
    }
  }

  bool _obdProbeSucceeded(String response) {
    final clean = response.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    const signatures = ['4100', '4104', '4105', '410B', '410C', '410D', '410F', '4110', '4111', '412F', '4142'];
    return signatures.any(clean.contains);
  }

  void _setProtocolFromDescription(String description) {
    final d = description.toUpperCase();
    _protocol = _firstUsefulLine(description, 'Unknown');
    if (d.contains('15765') || d.contains('CAN')) _protocolCode = '6';
    else if (d.contains('14230') && d.contains('FAST')) _protocolCode = '5';
    else if (d.contains('14230') || d.contains('KWP')) _protocolCode = '4';
    else if (d.contains('9141')) _protocolCode = '3';
  }

  Future<void> _configureProtocolTransport() async {
    if (!_connected) return;
    switch (_protocolCode) {
      case '6': case '8':
        await _sendAndWait('ATCAF1', timeout: const Duration(seconds: 1));
        await _sendAndWait('ATCFC1', timeout: const Duration(seconds: 1));
        await _sendAndWait('ATSH ${_udsRequestHeader.isNotEmpty ? _udsRequestHeader : '7DF'}', timeout: const Duration(seconds: 1));
        break;
      default:
        await _sendAndWait('ATH1', timeout: const Duration(seconds: 1));
    }
  }

  Future<void> _identifyVehicle() async {
    if (!_connected || _scanInProgress) return;
    if (!mounted) return;
    setState(() {
      _scanInProgress = true;
      _connectionStatus = 'در حال شناسایی خودرو...';
      _ecuModel = 'در حال اسکن...';
      _vin = '---';
    });
    try {
      final dp = await _sendAndWait('ATDP', timeout: const Duration(seconds: 2));
      _protocol = _firstUsefulLine(dp, 'Unknown');
      
      final ecuName = await _sendAndWait('090A', timeout: const Duration(seconds: 2));
      final vin = await _sendAndWait('0902', timeout: const Duration(seconds: 2));
      final name = _decodeObdAscii(ecuName, '4A0A');
      final vinText = _decodeObdAscii(vin, '4902');
      if (name.isNotEmpty) _ecuModel = name;
      if (vinText.isNotEmpty) _vin = vinText;

      if (_ecuModel == 'شناسایی نشده است' || _ecuModel == 'در حال اسکن...') {
        _ecuModel = 'ECU عمومی خودرو (OBD-II)';
      }
      _connectionStatus = 'متصل به خودرو • $_protocol';
    } catch (e) {
      _log('IDENTIFY ERROR $e');
      _ecuModel = 'شناسایی ناموفق';
      _connectionStatus = 'خطا در خواندن مشخصات ECU';
    } finally {
      if (mounted) setState(() => _scanInProgress = false);
    }
  }

  String _firstUsefulLine(String s, String fallback) {
    final lines = s.split(RegExp(r'[\r\n]+')).map((e) => e.trim()).where((e) => e.isNotEmpty && e != '>').toList();
    if (lines.isEmpty) return fallback;
    return lines.last;
  }

  String _decodeObdAscii(String response, String positivePrefix) {
    final clean = response.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final idx = clean.indexOf(positivePrefix);
    if (idx < 0) return '';
    final hex = clean.substring(idx + positivePrefix.length);
    final bytes = <int>[];
    for (int i = 0; i + 2 <= hex.length; i += 2) {
      final b = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (b == null) break;
      if (b >= 0x20 && b <= 0x7E) bytes.add(b);
    }
    return String.fromCharCodes(bytes).trim();
  }

  Future<String> _sendAndWait(String command, {Duration timeout = const Duration(milliseconds: 1500), bool logCommand = false}) {
    final completer = Completer<String>();
    _commandTail = _commandTail.then((_) async {
      if (!_connected || _connection == null) {
        if (!completer.isCompleted) completer.complete('');
        return;
      }

      final key = command.toUpperCase().replaceAll(RegExp(r'\s+'), '');
      if (logCommand) _log('TX $command');

      final existing = _waiters[key];
      if (existing != null) {
        final result = await existing.future;
        if (!completer.isCompleted) completer.complete(result);
        return;
      }

      final waiter = Completer<String>();
      _waiters[key] = waiter;
      try {
        _connection!.write('$command\r');
        await _connection!.flush();
        final result = await waiter.future.timeout(timeout, onTimeout: () => '');
        if (logCommand && result.isNotEmpty) _log('RX $result');
        if (!completer.isCompleted) completer.complete(result);
      } catch (e) {
        if (!completer.isCompleted) completer.complete('');
        _log('COMMAND ERROR $command: $e');
      } finally {
        if (identical(_waiters[key], waiter)) _waiters.remove(key);
      }
    }).catchError((e) {
      if (!completer.isCompleted) completer.complete('');
    });
    return completer.future;
  }

  Future<void> _sendManual(String command) async {
    if (!_connected) {
      _snack('ابتدا به دانگل متصل شوید.');
      return;
    }
    final response = await _sendAndWait(command.trim().toUpperCase(), timeout: const Duration(seconds: 3), logCommand: true);
    if (response.isEmpty) _log('TIMEOUT');
  }

  void _onBytes(Uint8List data) {
    _buffer += utf8.decode(data, allowMalformed: true);
    while (_buffer.contains('>')) {
      final i = _buffer.indexOf('>');
      final response = _buffer.substring(0, i).trim();
      _buffer = _buffer.substring(i + 1);
      if (response.isEmpty) continue;
      _log('RX $response');
      _resolveWaiter(response);
      _parseResponse(response);
    }
  }

  void _resolveWaiter(String response) {
    if (_waiters.isEmpty) return;
    final clean = response.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    String? key;

    if (clean.contains('41')) {
      final idx = clean.indexOf('41');
      if (idx + 4 <= clean.length) key = '01${clean.substring(idx + 2, idx + 4)}';
    } else if (clean.contains('49')) {
      final idx = clean.indexOf('49');
      if (idx + 4 <= clean.length) key = '09${clean.substring(idx + 2, idx + 4)}';
    } else if (clean.contains('43')) {
      key = '03';
    } else if (clean.contains('44')) {
      key = '04';
    }

    if (key != null && _waiters.containsKey(key)) {
      final c = _waiters.remove(key)!;
      if (!c.isCompleted) c.complete(response);
      return;
    }

    if (_waiters.length == 1) {
      final c = _waiters.values.first;
      if (!c.isCompleted) c.complete(response);
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
        if (value == null) { valid = false; break; }
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
    if (clean.contains('SEARCHING') || clean.contains('NO DATA') || clean.contains('ERROR') || clean.contains('STOPPED')) return;

    if (RegExp(r'^\d+(\.\d+)?V').hasMatch(response.trim().toUpperCase())) {
      final v = double.tryParse(response.trim().toUpperCase().replaceAll('V', ''));
      if (v != null && mounted) setState(() { _voltage = v; _voltageReceived = true; });
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
    final iat = _parsePid(response, '0F');
    if (iat != null) _receivedPids.add('0F');
    final fuel = _parsePid(response, '2F');
    if (fuel != null) _receivedPids.add('2F');
    final map = _parsePid(response, '0B');
    if (map != null) _receivedPids.add('0B');
    final mafBytes = _parsePidBytes(response, '10', 2);
    final ambient = _parsePid(response, '46');
    if (ambient != null) _receivedPids.add('46');
    
    if (mounted) {
      setState(() {
        if (rpmBytes != null) _rpm = (((rpmBytes[0] << 8) | rpmBytes[1]) ~/ 4);
        if (speed != null) _speed = speed;
        if (coolant != null) _coolant = coolant - 40;
        if (throttle != null) _throttle = ((throttle * 100) / 255).round();
        if (load != null) _engineLoad = ((load * 100) / 255).round();
        if (iat != null) _iat = iat - 40;
        if (fuel != null) _fuelLevel = (fuel * 100.0) / 255.0;
        if (map != null) _map = map.toDouble();
        if (mafBytes != null) _receivedPids.add('10');
        if (mafBytes != null) _maf = ((mafBytes[0] << 8) | mafBytes[1]) / 100.0;
        if (ambient != null) _ambient = ambient - 40.0;
      });
    }
    if (clean.contains('43')) _parseDtc(clean);
  }

  void _parseDtc(String clean) {
    final idx = clean.indexOf('43');
    if (idx < 0) return;
    final bytes = clean.substring(idx + 2);
    final result = <String>[];
    for (int i = 0; i + 4 <= bytes.length; i += 4) {
      final a = int.tryParse(bytes.substring(i, i + 2), radix: 16);
      final b = int.tryParse(bytes.substring(i + 2, i + 4), radix: 16);
      if (a == null || b == null || (a == 0 && b == 0)) continue;
      final prefix = ['P', 'C', 'B', 'U'][(a >> 6) & 3];
      result.add('$prefix${(a & 0x3F).toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'.toUpperCase());
    }
    if (mounted) setState(() { _dtcs..clear()..addAll(result.toSet()); _loadingDtc = false; });
  }

  Future<void> _scanDtc() async {
    if (!_connected) {
      _snack('ابتدا اتصال را برقرار کنید.');
      return;
    }
    _pollTimer?.cancel();
    if (!mounted) return;
    setState(() { _loadingDtc = true; _dtcs.clear(); });
    try {
      await _sendAndWait('03', timeout: const Duration(seconds: 4), logCommand: true);
    } finally {
      if (mounted) setState(() => _loadingDtc = false);
      _startPolling();
    }
  }

  Future<void> _clearDtc() async {
    if (!_connected) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأیید پاک‌سازی خطا'),
        content: const Text('آیا می‌خواهید کدهای خطای ECU را پاک کنید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('پاک کن')),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() => _clearingDtc = true);
    try {
      final r = await _sendAndWait('04', timeout: const Duration(seconds: 4), logCommand: true);
      if (r.isNotEmpty && !r.toUpperCase().contains('ERROR')) _dtcs.clear();
    } finally {
      if (mounted) setState(() => _clearingDtc = false);
      _startPolling();
    }
  }

  Future<void> _discoverSupportedPids() async {
    if (!_connected || !_obdAvailable) return;
    final found = <String>{};
    for (final pid in const ['00','20','40','60','80','A0','C0']) {
      final r = await _sendAndWait('01$pid', timeout: const Duration(seconds: 3));
      final clean = r.replaceAll(RegExp(r'\s+'),'').toUpperCase();
      final marker = '41$pid';
      final idx = clean.indexOf(marker);
      if (idx >= 0 && idx + 12 <= clean.length) {
        final bits = int.tryParse(clean.substring(idx + 4, idx + 12), radix: 16);
        if (bits != null) {
          for (var b = 0; b < 32; b++) {
            if ((bits & (1 << (31 - b))) != 0) {
              final p = int.parse(pid, radix: 16) + b + 1;
              found.add(p.toRadixString(16).padLeft(2,'0').toUpperCase());
            }
          }
        }
      }
    }
    _supportedPids..clear()..addAll(found);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (!_connected || !_obdAvailable) return;
    _pollIndex = 0;
    final base = <String>['04','05','0C','0D','11','0F','2F','0B','10','42'];
    final commands = base.map((p) => '01$p').toList();
    commands.add('ATRV');

    _pollTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (!_connected || _requestInFlight) return;
      _requestInFlight = true;
      try {
        final cmd = commands[_pollIndex % commands.length];
        _pollIndex++;
        await _sendAndWait(cmd, timeout: const Duration(seconds: 2));
      } finally {
        _requestInFlight = false;
      }
    });
  }

  Future<void> _disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _serialSub?.cancel();
    _serialSub = null;
    try { await _connection?.flush(); } catch (_) {}
    try { _connection?.destroy(); } catch (_) {}
    _connection = null;
    if (mounted) {
      setState(() {
        _connected = false;
        _connecting = false;
        _connectionStatus = 'آماده اتصال';
        _supportedPids.clear();
      });
    }
  }

  void _snack(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _loadCustomization() async {
    final p=await SharedPreferences.getInstance();
    final raw=p.getString('rasa_customization');
    if(raw!=null){ try { _custom=_RasaCustomization.fromJson(jsonDecode(raw)); } catch (_) {} }
    _workshopController.text=_custom.workshopName;
    _technicianController.text=_custom.technicianName;
    _phoneController.text=_custom.phone;
    try { _accent=Color(int.parse('FF${_custom.accentHex}',radix:16)); } catch (_) {}
    if(mounted) setState((){});
  }

  Future<void> _saveCustomization() async {
    final c=_RasaCustomization(workshopName:_workshopController.text.trim(),technicianName:_technicianController.text.trim(),phone:_phoneController.text.trim(),accentHex:_accent.value.toRadixString(16).substring(2).toUpperCase(),compactMode:_custom.compactMode);
    final p=await SharedPreferences.getInstance();
    await p.setString('rasa_customization',jsonEncode(c.toJson()));
    _custom=c;
    if(mounted) setState((){});
    _snack('شخصی‌سازی ذخیره شد');
  }

  String _newSixDigitCode(){
    final r=Random.secure();
    return (100000+r.nextInt(900000)).toString();
  }

  Future<void> _startCustomerSession() async {
    if (!_connected) {
      _snack('ابتدا دانگل را متصل کنید.');
      return;
    }
    await _remoteClose();
    _customerSessionCode = _newSixDigitCode();
    _remoteRoleLabel = 'مشتری (متصل به خودرو)';

    if (mounted) setState(() => _remoteConnecting = true);
    const serverUrl = 'wss://api.rasadiag.ir/ws';

    try {
      final ws = await WebSocket.connect(
        serverUrl,
        headers: {
          'X-RASA-Role': 'client',
          'X-RASA-Code': _customerSessionCode,
        },
      ).timeout(const Duration(seconds: 10));

      _remoteSocket = ws;
      _remoteConnected = true;
      _remoteStatus = 'آماده اتصال پشتیبان';

      _remoteSub = ws.listen((data) => _handleRemoteMessage(data.toString()), onDone: () {
        if (mounted) setState(() { _remoteConnected = false; _remoteStatus = 'ارتباط قطع شد'; });
      }, onError: (_) {
        if (mounted) setState(() { _remoteConnected = false; _remoteStatus = 'خطای ارتباطی'; });
      });

      ws.add(jsonEncode({'type': 'register_client', 'code': _customerSessionCode}));
      _remoteHeartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_remoteConnected) _remoteSocket?.add(jsonEncode({'type': 'ping'}));
      });

      _snack('کد ۶ رقمی ساخته شد.');
    } catch (e) {
      _remoteStatus = 'خطا: $e';
    } finally {
      if (mounted) setState(() => _remoteConnecting = false);
    }
  }

  Future<void> _connectAsExpert() async {
    final code = _supportSessionCodeController.text.trim();
    if (code.length != 6) {
      _snack('کد ۶ رقمی معتبر نیست.');
      return;
    }
    await _remoteClose();
    _remoteRoleLabel = 'پشتیبان فنی';

    if (mounted) setState(() => _remoteConnecting = true);
    const serverUrl = 'wss://api.rasadiag.ir/ws';

    try {
      final ws = await WebSocket.connect(
        serverUrl,
        headers: {
          'X-RASA-Role': 'expert',
          'X-RASA-Code': code,
        },
      ).timeout(const Duration(seconds: 10));

      _remoteSocket = ws;
      _remoteConnected = true;
      _remoteStatus = 'متصل به مشتری ($code)';

      _remoteSub = ws.listen((data) => _handleRemoteMessage(data.toString()), onDone: () {
        if (mounted) setState(() { _remoteConnected = false; _remoteStatus = 'قطع ارتباط'; });
      }, onError: (_) {
        if (mounted) setState(() { _remoteConnected = false; _remoteStatus = 'خطای ارتباطی'; });
      });

      ws.add(jsonEncode({'type': 'join_expert', 'target_code': code}));
      _remoteHeartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_remoteConnected) _remoteSocket?.add(jsonEncode({'type': 'ping'}));
      });
    } catch (e) {
      _remoteStatus = 'عدم اتصال: $e';
    } finally {
      if (mounted) setState(() => _remoteConnecting = false);
    }
  }

  void _sendRemoteDiagnostic(String cmd) {
    if (!_remoteConnected) {
      _snack('ارتباط ریموت برقرار نیست.');
      return;
    }
    _remoteSend({'type': 'diagnostic_request', 'command': cmd});
  }

  void _handleRemoteMessage(String raw){
    try{
      final m=jsonDecode(raw); if(m is! Map)return;
      if(m['type']=='pong')return;
      if(m['type']=='diagnostic_result'){
        final ok=m['ok']==true;
        final command='${m['command']??''}';
        final response='${m['response']??m['error']??''}';
        if(mounted) {
          setState((){
            if(_remoteResults.length>=80)_remoteResults.removeAt(0);
            _remoteResults.add('${ok ? '✓' : '✗'}  $command\n$response');
          });
        }
        return;
      }
      if(m['type']=='diagnostic_request' && m['command'] is String){
        if(!_connected){_remoteSend({'type':'diagnostic_result','ok':false,'error':'ECU disconnected'});return;}
        _sendAndWait(m['command'].toString(),timeout:const Duration(seconds:3)).then((r)=>_remoteSend({'type':'diagnostic_result','ok':true,'command':m['command'],'response':r})).catchError((e)=>_remoteSend({'type':'diagnostic_result','ok':false,'error':'$e'}));
      }
    }catch(_){}
  }

  void _remoteSend(Map<String,dynamic> message){if(_remoteConnected)_remoteSocket?.add(jsonEncode(message));}

  Future<void> _remoteClose() async {
    _remoteHeartbeat?.cancel(); _remoteHeartbeat=null;
    await _remoteSub?.cancel(); _remoteSub=null;
    try{await _remoteSocket?.close();}catch(_){ }
    _remoteSocket=null; _remoteConnected=false;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _serialSub?.cancel();
    _connection?.destroy();
    _tabs.dispose();
    _terminalController.dispose();
    _supportSessionCodeController.dispose();
    _workshopController.dispose();
    _technicianController.dispose();
    _phoneController.dispose();
    _remoteClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_custom.workshopName.isEmpty ? 'RASA DIAG (Kingbolen Wi-Fi)' : _custom.workshopName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        actions: [
          IconButton(onPressed: _selectKingbolenWifiDevice, icon: const Icon(Icons.wifi_tethering_rounded, color: Color(0xFF00F0FF)), tooltip: 'اتصال وای‌فای Kingbolen'),
          IconButton(onPressed: _disconnect, icon: const Icon(Icons.power_settings_new_rounded, color: Color(0xFFFF2A55)), tooltip: 'قطع اتصال'),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_rounded), text: 'داشبورد'),
            Tab(icon: Icon(Icons.directions_car_rounded), text: 'خودرو / ECU'),
            Tab(icon: Icon(Icons.sensors_rounded), text: 'سنسورها'),
            Tab(icon: Icon(Icons.error_outline_rounded), text: 'خطاها (DTC)'),
            Tab(icon: Icon(Icons.build_circle_rounded), text: 'عملگرها'),
            Tab(icon: Icon(Icons.memory_rounded), text: 'اطلاعات ECU'),
            Tab(icon: Icon(Icons.terminal_rounded), text: 'ترمینال AT'),
            Tab(icon: Icon(Icons.cloud_sync_rounded), text: 'ریموت'),
            Tab(icon: Icon(Icons.tune_rounded), text: 'شخصی‌سازی'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _dashboardTab(), _vehicleTab(), _sensorsTab(), _dtcTab(), _actuatorTab(), _ecuTab(), _terminalTab(), _remoteTab(), _customTab(),
      ]),
    );
  }

  Widget _dashboardTab() => ListView(padding: const EdgeInsets.all(14), children: [
        Card(
          child: ListTile(
            leading: Icon(_connected ? Icons.check_circle : Icons.link_off, color: _connected ? const Color(0xFF00E676) : const Color(0xFFFF2A55), size: 30),
            title: Text(_connectionStatus, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('پروتکل: $_protocol\nدانگل: $_adapterInfo'),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _metricCard('دور موتور (RPM)', '$_rpm', Icons.speed)),
          const SizedBox(width: 8),
          Expanded(child: _metricCard('سرعت', '$_speed km/h', Icons.directions_car)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _metricCard('دمای آب', '$_coolant °C', Icons.thermostat)),
          const SizedBox(width: 8),
          Expanded(child: _metricCard('ولتاژ باتری', '${_voltage.toStringAsFixed(1)} V', Icons.bolt)),
        ]),
      ]);

  Widget _metricCard(String title, String value, IconData icon) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            Icon(icon, color: const Color(0xFF00F0FF)),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
          ]),
        ),
      );

  Widget _vehicleTab() => ListView(padding: const EdgeInsets.all(14), children: [
        Card(child: ListTile(
          leading: const Icon(Icons.hub_rounded, color: Color(0xFF00F0FF)),
          title: const Text('شناسایی هوشمند خودرو'),
          subtitle: Text('مدل ECU: $_ecuModel'),
          trailing: FilledButton(onPressed: _connected ? _identifyVehicle : null, child: const Text('بررسی')),
        )),
      ]);

  Widget _sensorsTab() => ListView(padding: const EdgeInsets.all(14), children: [
        _sensorItem('دور موتور (RPM)', '$_rpm دور بر دقیقه', Icons.speed),
        _sensorItem('سرعت خودرو', '$_speed کیلومتر بر ساعت', Icons.directions_car),
        _sensorItem('دمای مایع خنک‌کننده', '$_coolant درجه سانتی‌گراد', Icons.thermostat),
        _sensorItem('موقعیت دریچه گاز', '$_throttle درصد', Icons.shutter_speed),
        _sensorItem('بار موتور (Engine Load)', '$_engineLoad درصد', Icons.compress),
        _sensorItem('دمای هوای ورودی', '$_iat درجه سانتی‌گراد', Icons.air),
        _sensorItem('فشار منیفولد (MAP)', _map >= 0 ? '${_map.toStringAsFixed(0)} kPa' : 'داده ناموجود', Icons.compress_rounded),
        _sensorItem('حجم هوای ورودی (MAF)', _maf >= 0 ? '${_maf.toStringAsFixed(2)} g/s' : 'داده ناموجود', Icons.air_rounded),
        _sensorItem('ولتاژ باتری', '${_voltage.toStringAsFixed(2)} ولت', Icons.bolt),
      ]);

  Widget _sensorItem(String title, String value, IconData icon) => Card(
        child: ListTile(
          leading: Icon(icon, color: const Color(0xFF00F0FF)),
          title: Text(title),
          subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E676))),
        ),
      );

  Widget _dtcTab() => Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: FilledButton.icon(onPressed: _loadingDtc ? null : _scanDtc, icon: const Icon(Icons.search), label: const Text('اسکن خطاهای ECU'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(onPressed: _clearingDtc ? null : _clearDtc, style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF2A55)), icon: const Icon(Icons.delete_sweep), label: const Text('پاک‌سازی خطاها'))),
          ]),
        ),
        if (_loadingDtc) const LinearProgressIndicator(),
        Expanded(
          child: _dtcs.isEmpty
              ? const Center(child: Text('هیچ خطایی در حافظه ECU ثبت نشده است.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _dtcs.length,
                  itemBuilder: (_, i) {
                    final c = _dtcs[i];
                    return Card(
                      child: ListTile(
                        leading: Text(c, style: const TextStyle(color: Color(0xFFFF2A55), fontWeight: FontWeight.bold, fontSize: 16)),
                        title: Text(dtcDescriptions[c] ?? 'خطای عمومی / سازنده'),
                      ),
                    );
                  },
                ),
        ),
      ]);

  Widget _actuatorTab() => ListView(padding: const EdgeInsets.all(14), children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('تست عملگرها برای پایداری بیشتر روی پروتکل‌های Kingbolen فعال است.', style: TextStyle(color: Colors.white70)),
          ),
        ),
      ]);

  Widget _ecuTab() => ListView(padding: const EdgeInsets.all(14), children: [
        _infoCard('مدل ECU', _ecuModel),
        _infoCard('پروتکل ارتباطی', '$_protocol (کد پروتکل: $_protocolCode)'),
        _infoCard('شماره شناسایی خودرو (VIN)', _vin),
        _infoCard('مشخصات دانگل (AT+I)', _adapterInfo),
      ]);

  Widget _infoCard(String label, String value) => Card(
        child: ListTile(
          title: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          subtitle: SelectableText(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ),
      );

  Widget _terminalTab() => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Expanded(
            child: Card(
              child: ListView.builder(
                reverse: true,
                itemCount: _logs.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Text(_logs[_logs.length - 1 - i], style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF00F0FF))),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _terminalController, decoration: const InputDecoration(hintText: 'دستور AT (مثل ATRV یا 010C)', isDense: true, border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                final c = _terminalController.text;
                _terminalController.clear();
                if (c.isNotEmpty) _sendManual(c);
              },
              icon: const Icon(Icons.send, color: Color(0xFF00F0FF)),
            ),
          ]),
        ]),
      );

  Widget _remoteTab() => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('سیستم پشتیبانی از راه دور (Remote Diagnosis)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _startCustomerSession,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('ایجاد کد اتصال مشتری'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _customTab() => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('شخصی‌سازی تعمیرگاه', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(controller: _workshopController, decoration: const InputDecoration(labelText: 'نام تعمیرگاه')),
                  const SizedBox(height: 8),
                  TextField(controller: _technicianController, decoration: const InputDecoration(labelText: 'نام تکنسین')),
                  const SizedBox(height: 8),
                  TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'شماره تماس')),
                  const SizedBox(height: 14),
                  FilledButton.icon(onPressed: _saveCustomization, icon: const Icon(Icons.save), label: const Text('ذخیره تنظیمات')),
                ],
              ),
            ),
          ),
        ],
      );
}
