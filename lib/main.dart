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
  ProtocolCandidate('1','ATSP1','SAE J1850 PWM 41.6 kbps'),
  ProtocolCandidate('2','ATSP2','SAE J1850 VPW 10.4 kbps'),
  ProtocolCandidate('3','ATSP3','ISO 9141-2'),
  ProtocolCandidate('4','ATSP4','ISO 14230-4 KWP 5-baud'),
  ProtocolCandidate('5','ATSP5','ISO 14230-4 KWP Fast Init'),
  ProtocolCandidate('6','ATSP6','ISO 15765-4 CAN 11-bit 500k'),
  ProtocolCandidate('7','ATSP7','ISO 15765-4 CAN 29-bit 500k'),
  ProtocolCandidate('8','ATSP8','ISO 15765-4 CAN 11-bit 250k'),
  ProtocolCandidate('9','ATSP9','ISO 15765-4 CAN 29-bit 250k'),
  ProtocolCandidate('A','ATSPA','SAE J1939 CAN 29-bit 250k'),
  ProtocolCandidate('B','ATSPB','USER CAN 1'),
  ProtocolCandidate('C','ATSPC','USER CAN 2'),
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
  String get confidenceText => confidence == EcuConfidence.verified ? 'تأییدشده' : confidence == EcuConfidence.partial ? 'تأیید خانواده / نیازمند Trace' : 'نیازمند Trace';
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
    id: 'IKCO-206-SAGEM-S2000', manufacturer: 'Sagem', vehicleFamily: 'Iran Khodro',
    model: 'Peugeot 206 / TU5', engine: 'TU5', ecuManufacturer: 'Sagem', ecuModel: 'S2000',
    protocolCode: '5', protocolName: 'ISO 14230-4 KWP Fast Init', transport: 'K-LINE',
    services: ['KWP DTC', 'Live Data', 'Actuator Control'],
    livePids: ['RPM', 'ECT', 'TPS', 'MAP', 'IAT', 'Battery'],
    confidence: EcuConfidence.partial,
    sourceNote: 'Sagem S2000 actuator/live-data catalog is public.',
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
    id: 'JAC-S5-DELPHI-MT80', manufacturer: 'JAC', vehicleFamily: 'Kerman Motor',
    model: 'S5', engine: '1.5T / 2.0', ecuManufacturer: 'Delphi', ecuModel: 'MT80',
    protocolCode: '6', protocolName: 'ISO 15765-4 CAN 11-bit 500k', transport: 'CAN11-500',
    requestHeader: '7E0',
    services: ['OBD-II', 'Live Data', 'DTC', 'Actuator Control'],
    confidence: EcuConfidence.partial,
    sourceNote: 'Delphi MT80 CAN ECU family.',
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
    id: 'CHERY-UDS-ODOMETER',
    protocol: DiagnosticProtocol.udsCan,
    ecuFamily: 'MVM / Fownix',
    serviceHex: '22',
    didHex: 'F1A5',
    dataOffset: 3,
    dataLength: 4,
    scale: 0.1,
    unit: 'KM',
    verification: 'تأییدشده برای شبکه CAN خانواده چری و ام‌وی‌ام',
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
  });
}

const List<ActuatorTestDefinition> verifiedActuatorTests = [
  ActuatorTestDefinition(
    id: 'FAN_LOW_BOSCH',
    name: 'فن خنک‌کننده (دور کند)',
    group: 'خنک‌کاری',
    icon: Icons.air_rounded,
    protocol: ActuatorProtocolType.uds,
    supportedEcuFamilies: ['IKCO-DENA-EF7-ME749', 'CHERY-MVM-UDS-CAN', 'JAC-S5-DELPHI-MT80'],
    startHex: '2F410A0301',
    stopHex: '2F410A00',
    autoStopSeconds: 5,
  ),
  ActuatorTestDefinition(
    id: 'FAN_HIGH_BOSCH',
    name: 'فن خنک‌کننده (دور تند)',
    group: 'خنک‌کاری',
    icon: Icons.air_rounded,
    protocol: ActuatorProtocolType.uds,
    supportedEcuFamilies: ['IKCO-DENA-EF7-ME749', 'CHERY-MVM-UDS-CAN', 'JAC-S5-DELPHI-MT80'],
    startHex: '2F410B0301',
    stopHex: '2F410B00',
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
  ActuatorTestDefinition(
    id: 'EVAP_CANISTER',
    name: 'شیر برقی کنیستر',
    group: 'هوا / آلایندگی',
    icon: Icons.filter_alt_rounded,
    protocol: ActuatorProtocolType.uds,
    supportedEcuFamilies: ['IKCO-DENA-EF7-ME749'],
    startHex: '2F41080301',
    stopHex: '2F410800',
    autoStopSeconds: 5,
  ),
  ActuatorTestDefinition(
    id: 'INJECTOR_1_KWP',
    name: 'انژکتور ۱ (قطع پاشش/تحریک)',
    group: 'سوخت‌رسانی',
    icon: Icons.water_drop_rounded,
    protocol: ActuatorProtocolType.kwp,
    supportedEcuFamilies: ['IKCO-206-TU5-ME744', 'IKCO-206-SAGEM-S2000'],
    startHex: '310101',
    stopHex: '310100',
    autoStopSeconds: 3,
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

enum _ActuatorSourceType { obdPid, udsDid, unavailable }

class _ActuatorStatusDefinition {
  final String name;
  final String group;
  final IconData icon;
  final _ActuatorSourceType source;
  final String idHex;
  final int byteOffset;
  final int mask;
  final int onValue;
  final int offValue;
  const _ActuatorStatusDefinition({
    required this.name,
    required this.group,
    required this.icon,
    required this.source,
    this.idHex = '',
    this.byteOffset = 0,
    this.mask = 0xFF,
    this.onValue = 1,
    this.offValue = 0,
  });
}

class RasaDashboardScreen extends StatefulWidget {
  const RasaDashboardScreen({super.key});
  @override
  State<RasaDashboardScreen> createState() => _RasaDashboardScreenState();
}

class _RasaDashboardScreenState extends State<RasaDashboardScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  BluetoothConnection? _connection;
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
  bool _isKwp = false;

  ActuatorTestDefinition? _activeRunningTest;
  Timer? _actuatorCountdownTimer;
  int _actuatorRemainingSeconds = 0;
  bool _actuatorActionInProgress = false;

  EcuProfile _profile = ecuProfiles.last;
  EcuDatabaseEntry? _matchedEcu;
  final List<EcuDatabaseEntry> _dbMatches = [];
  final List<String> _discoveryTrace = [];
  String _databaseStatus = 'هنوز تطبیق ECU انجام نشده است';
  bool _databaseScanning = false;
  String _hwId = '---';
  String _swId = '---';
  String _protocol = 'Unknown';
  String _protocolCode = '0';
  bool _protocolScanRunning = false;
  String _ecuModel = 'شناسایی نشده';
  String _ecuSoftware = '---';
  String _vin = '---';
  String _adapterInfo = '---';
  String _connectionStatus = 'آماده اتصال';
  String _udsRequestHeader = '';
  String _udsResponseHeader = '';
  String _discoveryMethod = '---';
  final List<String> _udsNrcs = [];

  int _rpm = 0, _speed = 0, _coolant = 0, _throttle = 0, _engineLoad = 0, _iat = 0;
  double _voltage = 0, _o2 = 0, _odometer = 0, _fuelLevel = -1, _map = -1, _maf = -1, _ambient = -100;
  String _odometerStatus = 'استعلام نشده';
  bool _loadingDtc = false;
  bool _clearingDtc = false;
  int _pollIndex = 0;
  final Set<String> _supportedPids = {};
  final Map<String, String> _actuatorStates = {};
  final Map<String, DateTime> _actuatorChangedAt = {};
  final Map<String, String> _actuatorChangeText = {};
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

  Future<bool> _requestBluetoothPermissions() async {
    if (!Platform.isAndroid) return true;
    final statuses = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    final connect = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    final scan = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    if (!connect || !scan) {
      final loc = await Permission.location.request();
      if (!loc.isGranted && (!connect || !scan)) return false;
    }
    return true;
  }

  Future<void> _selectBluetoothDevice() async {
    if (!await _requestBluetoothPermissions()) {
      _snack('مجوزهای لازم بلوتوث صادر نشده است.');
      return;
    }
    List<BluetoothDevice> devices;
    try {
      devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (e) {
      _snack('خطای دسترسی به بلوتوث: $e');
      return;
    }
    if (!mounted) return;
    final selected = await showModalBottomSheet<BluetoothDevice>(
      context: context,
      backgroundColor: const Color(0xFF10141E),
      builder: (_) => SafeArea(
        child: SizedBox(
          height: min(MediaQuery.of(context).size.height * .65, 560),
          child: devices.isEmpty
              ? const Center(child: Text('دانگل Pair شده‌ای پیدا نشد.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: devices.length,
                  itemBuilder: (_, i) {
                    final d = devices[i];
                    return ListTile(
                      leading: const Icon(Icons.bluetooth, color: Color(0xFF00F0FF)),
                      title: Text(d.name ?? 'OBD Adapter'),
                      subtitle: Text(d.address),
                      onTap: () => Navigator.pop(context, d),
                    );
                  },
                ),
        ),
      ),
    );
    if (selected != null) await _connect(selected);
  }

  Future<void> _connect(BluetoothDevice device) async {
    if (_connecting) return;
    await _disconnect();
    setState(() {
      _connecting = true;
      _connectionStatus = 'در حال اتصال به ${device.name ?? device.address}';
    });
    try {
      final c = await BluetoothConnection.toAddress(device.address);
      _connection = c;
      _serialSub = c.input?.listen(_onBytes, onError: (e) => _log('RX ERROR $e'), onDone: () {
        if (mounted) setState(() => _connected = false);
      });
      setState(() {
        _connected = true;
        _connecting = false;
        _connectionStatus = 'دانگل متصل؛ در حال شناسایی ECU';
      });
      _log('CONNECTED ${device.name ?? device.address}');
      await _initializeAdapter();
      await _identifyVehicle();
      _startPolling();
    } catch (e) {
      setState(() {
        _connecting = false;
        _connected = false;
        _connectionStatus = 'خطا در اتصال';
      });
      _snack('اتصال ناموفق: $e');
    }
  }

  Future<void> _initializeAdapter() async {
    await _sendAndWait('ATZ', timeout: const Duration(seconds: 3), logCommand: true);
    await Future.delayed(const Duration(milliseconds: 300));
    await _sendAndWait('ATE0', timeout: const Duration(seconds: 1), logCommand: true);
    await _sendAndWait('ATL0', timeout: const Duration(seconds: 1), logCommand: true);
    await _sendAndWait('ATS0', timeout: const Duration(seconds: 1), logCommand: true);
    await _sendAndWait('ATH1', timeout: const Duration(seconds: 1), logCommand: true);
    final ati = await _sendAndWait('ATI', timeout: const Duration(seconds: 1), logCommand: true);
    _adapterInfo = _firstUsefulLine(ati, 'ELM/OBD adapter');
    await _sendAndWait('ATAL', timeout: const Duration(seconds: 1), logCommand: true);
    await _sendAndWait('ATAT1', timeout: const Duration(seconds: 1), logCommand: true);
    await _sendAndWait('ATSP0', timeout: const Duration(seconds: 2), logCommand: true);
    final probe = await _sendAndWait('0100', timeout: const Duration(seconds: 2), logCommand: true);
    if (_obdProbeSucceeded(probe)) {
      final dp = await _sendAndWait('ATDP', timeout: const Duration(seconds: 1), logCommand: true);
      _setProtocolFromDescription(dp);
    } else {
      await _scanAllElmProtocols();
    }
    await _configureProtocolTransport();
    if (_protocolCode != 'A') { await _discoverSupportedPids(); }
    _log('PROTOCOL $_protocol ($_protocolCode)');
  }

  bool _obdProbeSucceeded(String response) {
    final clean = response.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    const signatures = ['4100', '4105', '410C', '410D', '410F', '4111', '412F'];
    return signatures.any(clean.contains);
  }

  void _setProtocolFromDescription(String description) {
    final d = description.toUpperCase();
    _protocol = _firstUsefulLine(description, 'Unknown');
    if (d.contains('J1939')) _protocolCode = 'A';
    else if (d.contains('15765') && d.contains('29') && d.contains('250')) _protocolCode = '9';
    else if (d.contains('15765') && d.contains('29')) _protocolCode = '7';
    else if (d.contains('15765') && d.contains('250')) _protocolCode = '8';
    else if (d.contains('15765') || d.contains('CAN')) _protocolCode = '6';
    else if (d.contains('14230') && d.contains('FAST')) _protocolCode = '5';
    else if (d.contains('14230') || d.contains('KWP')) _protocolCode = '4';
    else if (d.contains('9141')) _protocolCode = '3';
    else if (d.contains('J1850') && d.contains('PWM')) _protocolCode = '1';
    else if (d.contains('J1850')) _protocolCode = '2';
  }

  Future<void> _scanAllElmProtocols() async {
    if (!_connected || _protocolScanRunning) return;
    _protocolScanRunning = true;
    _pollTimer?.cancel();
    if (mounted) setState(() => _connectionStatus = 'در حال اسکن پروتکل‌های ارتباطی...');
    try {
      for (final candidate in elmProtocolCandidates.skip(1)) {
        if (!_connected) break;
        await _sendAndWait(candidate.command, timeout: const Duration(seconds: 2), logCommand: true);
        final dp = await _sendAndWait('ATDP', timeout: const Duration(milliseconds: 900));
        if (candidate.code == 'A') {
          if (dp.toUpperCase().contains('J1939')) {
            _protocolCode = 'A'; _protocol = candidate.name; break;
          }
        } else {
          var probe = await _sendAndWait('0100', timeout: const Duration(milliseconds: 1300), logCommand: true);
          if (!_obdProbeSucceeded(probe)) {
            for (final test in const ['010C', '010D', '0105', '010F', '012F']) {
              probe = await _sendAndWait(test, timeout: const Duration(milliseconds: 1000), logCommand: true);
              if (_obdProbeSucceeded(probe)) break;
            }
          }
          if (_obdProbeSucceeded(probe)) {
            _protocolCode = candidate.code; _protocol = candidate.name; break;
          }
        }
      }
      if (_protocolCode == '0') {
        final dp = await _sendAndWait('ATDP', timeout: const Duration(seconds: 1));
        _setProtocolFromDescription(dp);
      }
    } finally {
      _protocolScanRunning = false;
      if (mounted) setState(() => _connectionStatus = 'پروتکل: $_protocol');
    }
  }

  Future<void> _configureProtocolTransport() async {
    if (!_connected) return;
    switch (_protocolCode) {
      case '6': case '8':
        await _sendAndWait('ATCAF1', timeout: const Duration(seconds: 1));
        await _sendAndWait('ATCFC1', timeout: const Duration(seconds: 1));
        await _sendAndWait('ATSH ${_udsRequestHeader.isNotEmpty ? _udsRequestHeader : '7DF'}', timeout: const Duration(seconds: 1));
        break;
      case '7': case '9':
        await _sendAndWait('ATCAF1', timeout: const Duration(seconds: 1));
        await _sendAndWait('ATCFC1', timeout: const Duration(seconds: 1));
        break;
      case 'A':
        await _sendAndWait('ATJE', timeout: const Duration(seconds: 1));
        await _sendAndWait('ATJHF1', timeout: const Duration(seconds: 1));
        break;
      default:
        await _sendAndWait('ATH1', timeout: const Duration(seconds: 1));
    }
  }

  Future<void> _applyProfile(EcuProfile p) async {
    if (!_connected) return;
    _pollTimer?.cancel();
    final db = rasaEcuDatabase.where((e) => p.title.toUpperCase().contains(e.ecuModel.toUpperCase()) || p.model.toUpperCase().contains(e.ecuModel.toUpperCase())).toList();
    _matchedEcu = db.isEmpty ? null : db.first;
    _databaseStatus = _matchedEcu == null ? 'پروفایل عمومی؛ نیازمند Trace' : '${_matchedEcu!.title} • ${_matchedEcu!.confidenceText}';
    setState(() {
      _profile = p;
      _supportsOdometer = false;
      _odometer = 0;
      _odometerStatus = 'استعلام نشده';
    });
    final candidate = p.protocol == 'OBD-II'
        ? elmProtocolCandidates.first
        : p.protocol.contains('KWP') ? elmProtocolCandidates.firstWhere((e) => e.code == '5')
        : p.protocol.contains('CAN') ? elmProtocolCandidates.firstWhere((e) => e.code == '6')
        : null;
    if (candidate != null) { _protocolCode = candidate.code; _protocol = candidate.name; await _sendAndWait(candidate.command, timeout: const Duration(seconds: 2)); }
    await _configureProtocolTransport();
    _startPolling();
  }

  EcuProfile _profileFromDatabase(EcuDatabaseEntry e) {
    final p = e.protocolCode == '4' || e.protocolCode == '5' ? 'KWP2000' :
        e.protocolCode == '6' || e.protocolCode == '7' || e.protocolCode == '8' || e.protocolCode == '9' ? 'CAN 500K' :
        e.protocolName;
    return EcuProfile(
      manufacturer: e.ecuManufacturer,
      model: e.ecuModel,
      family: '${e.vehicleFamily} • ${e.model}',
      protocol: p,
      header: e.requestHeader == null ? null : 'ATSH ${e.requestHeader}',
      functionalHeader: 'ATSH 7DF',
    );
  }

  bool _containsAny(String text, Iterable<String> terms) {
    final u = text.toUpperCase();
    return terms.any((t) => u.contains(t.toUpperCase()));
  }

  void _rankDatabaseMatches({String ecuText = '', String vinText = ''}) {
    final text = '$ecuText $vinText $_ecuModel ${_profile.family} ${_profile.model} $_hwId $_swId'.toUpperCase();
    final scored = <MapEntry<int, EcuDatabaseEntry>>[];
    for (final e in rasaEcuDatabase) {
      var score = 0;
      final hay = '${e.manufacturer} ${e.vehicleFamily} ${e.model} ${e.ecuManufacturer} ${e.ecuModel} ${e.hardware ?? ''} ${e.software ?? ''}'.toUpperCase();
      if (_containsAny(text, [e.ecuModel])) score += 8;
      if (_containsAny(text, [e.ecuManufacturer])) score += 4;
      if (_containsAny(text, [e.model])) score += 5;
      if (e.hardware != null && text.contains(e.hardware!.toUpperCase())) score += 12;
      if (e.software != null && text.contains(e.software!.toUpperCase())) score += 12;
      if (hay.isNotEmpty && score > 0) scored.add(MapEntry(score, e));
    }
    scored.sort((a,b) => b.key.compareTo(a.key));
    _dbMatches
      ..clear()
      ..addAll(scored.take(8).map((e) => e.value));
    if (scored.isNotEmpty) {
      _matchedEcu = scored.first.value;
      _profile = _profileFromDatabase(_matchedEcu!);
      _databaseStatus = '${_matchedEcu!.title} • ${_matchedEcu!.confidenceText}';
    } else {
      _matchedEcu = null;
      _databaseStatus = 'تطبیق دقیق پیدا نشد؛ Discovery/Trace لازم است';
    }
  }

  String _formatHex2(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();

  bool _isUdsPositiveForDid(String response, int did) {
    final pdu = _isoTpReassemble(response)?.payload ?? _hexBytes(response);
    return pdu.length >= 3 && pdu[0] == 0x62 && pdu[1] == ((did >> 8) & 0xFF) && pdu[2] == (did & 0xFF);
  }

  Future<bool> _tryUdsHeader(String requestHeader) async {
    if (!_connected) return false;
    await _sendAndWait('ATSH $requestHeader', timeout: const Duration(milliseconds: 700));
    final r = await _udsRequest('22F190', timeout: const Duration(milliseconds: 1800));
    final ok = _isUdsPositiveForDid(r, 0xF190);
    if (ok) {
      _udsRequestHeader = requestHeader;
      final responseId = _extractCanId(r);
      if (responseId.isNotEmpty) _udsResponseHeader = responseId;
      _discoveryTrace.add('UDS ADDRESS $requestHeader => ${responseId.isEmpty ? 'response' : responseId} / F190 OK');
      return true;
    }
    _discoveryTrace.add('UDS ADDRESS $requestHeader => NO F190');
    return false;
  }

  String _extractCanId(String response) {
    for (final line in response.toUpperCase().split(RegExp(r'[\r\n]+'))) {
      final m = RegExp(r'^([0-9A-F]{3,8})\s+').firstMatch(line.trim());
      if (m != null) return m.group(1)!;
    }
    return '';
  }

  Future<void> _discoverUdsPhysicalAddress() async {
    await _sendAndWait('ATCAF1', timeout: const Duration(seconds: 1));
    await _sendAndWait('ATCFC1', timeout: const Duration(seconds: 1));
    final candidates = <String>{
      if (_matchedEcu?.requestHeader != null) _matchedEcu!.requestHeader!,
      ...?_matchedEcu?.requestHeaderCandidates,
      if (_udsRequestHeader.isNotEmpty) _udsRequestHeader,
      ...List.generate(8, (i) => '7E${i.toRadixString(16).toUpperCase()}'),
    };
    for (final h in candidates) {
      if (!RegExp(r'^[0-9A-Fa-f]{3}$').hasMatch(h)) continue;
      if (await _tryUdsHeader(h.toUpperCase())) {
        _discoveryMethod = 'UDS F190 physical-address discovery';
        return;
      }
    }
    _udsRequestHeader = '';
    _udsResponseHeader = '';
    _discoveryMethod = 'No verified UDS physical address';
  }

  Future<void> _readUdsIdentificationSet() async {
    if (_udsRequestHeader.isEmpty) return;
    await _sendAndWait('ATSH $_udsRequestHeader', timeout: const Duration(milliseconds: 700));
    final dids = _matchedEcu?.identificationDids ?? const [0xF190, 0xF187, 0xF188, 0xF189, 0xF191, 0xF194, 0xF195];
    for (final did in dids) {
      final r = await _udsReadDid(did);
      final pdu = _isoTpReassemble(r)?.payload ?? _hexBytes(r);
      if (pdu.length < 3 || pdu[0] != 0x62 || pdu[1] != ((did >> 8) & 0xFF) || pdu[2] != (did & 0xFF)) continue;
      final value = String.fromCharCodes(pdu.sublist(3).where((b) => b >= 0x20 && b <= 0x7E)).trim();
      final hex = pdu.sublist(3).map(_formatHex2).join();
      _discoveryTrace.add('UDS 22${did.toRadixString(16).padLeft(4,'0').toUpperCase()} @ $_udsRequestHeader => ${value.isEmpty ? hex : value}');
      if (did == 0xF190 && value.isNotEmpty) _vin = value;
      if (did == 0xF187 && value.isNotEmpty) _hwId = value;
      if ((did == 0xF188 || did == 0xF194) && value.isNotEmpty) _swId = value;
      if (did == 0xF191 && value.isNotEmpty) _hwId = value;
      if (did == 0xF195 && value.isNotEmpty) _swId = value;
    }
  }

  Future<void> _discoverEcuDatabase() async {
    if (!_connected || _databaseScanning) return;
    _databaseScanning = true;
    _pollTimer?.cancel();
    if (mounted) setState(() => _databaseStatus = 'در حال Discovery و تطبیق با بانک ECU...');
    try {
      _discoveryTrace.clear();
      _hwId = '---';
      _swId = '---';
      var ecuName = '';
      var vin = '';

      final nameRaw = await _sendAndWait('090A', timeout: const Duration(seconds: 2), logCommand: true);
      final vinRaw = await _sendAndWait('0902', timeout: const Duration(seconds: 2), logCommand: true);
      ecuName = _decodeObdAscii(nameRaw, '4A0A');
      vin = _decodeObdAscii(vinRaw, '4902');
      if (ecuName.isNotEmpty) _ecuModel = ecuName;
      if (vin.isNotEmpty) _vin = vin;
      _discoveryTrace.add('OBD 090A => ${ecuName.isEmpty ? 'NO DATA' : ecuName}');
      _discoveryTrace.add('OBD 0902 => ${vin.isEmpty ? 'NO DATA' : vin}');

      if (_protocolCode == '6' || _protocolCode == '7' || _protocolCode == '8' || _protocolCode == '9') {
        await _discoverUdsPhysicalAddress();
        if (_udsRequestHeader.isNotEmpty) {
          await _readUdsIdentificationSet();
        }
      }

      _rankDatabaseMatches(ecuText: ecuName, vinText: vin);
      if (mounted) setState(() {});
    } finally {
      _databaseScanning = false;
      _startPolling();
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveDiscoverySnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final record = jsonEncode({
      'time': DateTime.now().toIso8601String(), 'protocol': _protocol, 'protocolCode': _protocolCode,
      'ecuModel': _ecuModel, 'vin': _vin, 'hardware': _hwId, 'software': _swId,
      'databaseMatch': _matchedEcu?.id, 'trace': _discoveryTrace,
    });
    final old = prefs.getStringList('rasa_ecu_traces') ?? <String>[];
    old.add(record);
    while (old.length > 50) old.removeAt(0);
    await prefs.setStringList('rasa_ecu_traces', old);
    _snack('Trace ECU ذخیره شد.');
  }

  Future<void> _identifyVehicle() async {
    if (!_connected || _scanInProgress) return;
    setState(() {
      _scanInProgress = true;
      _connectionStatus = 'در حال شناسایی ECU';
      _ecuModel = 'در حال شناسایی...';
      _vin = '---';
      _ecuSoftware = '---';
    });
    try {
      final dp = await _sendAndWait('ATDP', timeout: const Duration(seconds: 2));
      final dpClean = dp.toUpperCase();
      _protocol = _firstUsefulLine(dp, 'Unknown');
      _isKwp = dpClean.contains('ISO 14230') || dpClean.contains('KWP') || dpClean.contains('ISO 9141');

      final ecuName = await _sendAndWait('090A', timeout: const Duration(seconds: 2));
      final vin = await _sendAndWait('0902', timeout: const Duration(seconds: 2));
      final name = _decodeObdAscii(ecuName, '4A0A');
      final vinText = _decodeObdAscii(vin, '4902');
      if (name.isNotEmpty) _ecuModel = name;
      if (vinText.isNotEmpty) _vin = vinText;

      if (_profile.header != null && !_isKwp) {
        await _sendAndWait(_profile.header!, timeout: const Duration(seconds: 1));
      }
      final rpm = await _sendAndWait('010C', timeout: const Duration(seconds: 2));
      if (_parsePid(rpm, '0C') != null) {
        _ecuModel = _ecuModel == 'در حال شناسایی...' || _ecuModel == 'شناسایی نشده' ? 'ECU OBD-II' : _ecuModel;
      }
      _ecuSoftware = 'از ECU عمومی قابل تشخیص نیست';
      if (_profile.protocol.contains('UDS') || _profile.protocol.contains('CAN')) {
        try {
          await _sendAndWait('ATCAF1', timeout: const Duration(seconds: 1));
          await _sendAndWait('ATCFC1', timeout: const Duration(seconds: 1));
          if (_profile.header != null) await _sendAndWait(_profile.header!, timeout: const Duration(seconds: 1));
          final udsResponse = await _udsReadDid(0xF190);
          final udsVin = _decodeUdsVin(udsResponse);
          if (udsVin.isNotEmpty) _vin = udsVin;
        } catch (e) {
          _log('UDS IDENTIFY ERROR $e');
        }
      }
      _rankDatabaseMatches(ecuText: name, vinText: vinText);
      _connectionStatus = 'ECU پاسخ‌گو • $_databaseStatus';
    } catch (e) {
      _log('IDENTIFY ERROR $e');
      _ecuModel = 'شناسایی ناموفق';
      _connectionStatus = 'دانگل متصل / ECU نامشخص';
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
        _connection!.output.add(Uint8List.fromList(utf8.encode('$command\r')));
        await _connection!.output.allSent;
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

    final clean=response.replaceAll(RegExp(r'\s+'),'').toUpperCase();
    final pdu=_isoTpReassemble(response)?.payload ?? _hexBytes(clean);
    String? key;

    if(pdu.isNotEmpty){
      final service=pdu[0];
      final positiveToOriginal=<int,int>{
        0x50:0x10,
        0x54:0x14,
        0x59:0x19,
        0x62:0x22,
        0x6F:0x2F,
        0x71:0x31,
        0x7E:0x3E,
      };
      final original=positiveToOriginal[service];
      if(original!=null) key=_findUdsWaiterByService(original);

      if(service==0x7F && pdu.length>=2){
        key=_findUdsWaiterByService(pdu[1]);
      }
    }

    if(key==null && clean.contains('41')){
      final idx=clean.indexOf('41');
      if(idx+4<=clean.length) key='01${clean.substring(idx+2,idx+4)}';
    }else if(key==null && clean.contains('49')){
      final idx=clean.indexOf('49');
      if(idx+4<=clean.length) key='09${clean.substring(idx+2,idx+4)}';
    }else if(key==null && clean.contains('43')){
      key='03';
    }else if(key==null && clean.contains('44')){
      key='04';
    }

    if(key!=null && _waiters.containsKey(key)){
      final c=_waiters.remove(key)!;
      if(!c.isCompleted)c.complete(response);
      return;
    }

    if(_waiters.length==1){
      final c=_waiters.values.first;
      if(!c.isCompleted)c.complete(response);
    }
  }

  String? _findUdsWaiterByService(int service){
    for(final key in _waiters.keys){
      if(key.startsWith('UDS$service:')) return key;
    }
    return null;
  }

  List<int>? _parsePidBytes(String response, String pid, int count) {
    final clean = response.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final idx = clean.indexOf('41$pid');
    if (idx < 0) return null;
    final start = idx + 4;
    final end = start + (count * 2);
    if (end > clean.length) return null;
    final out = <int>[];
    for (int i = start; i < end; i += 2) {
      final b = int.tryParse(clean.substring(i, i + 2), radix: 16);
      if (b == null) return null;
      out.add(b);
    }
    return out;
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
      if (v != null && mounted) setState(() => _voltage = v);
    }

    final rpmBytes = _parsePidBytes(response, '0C', 2);
    if (rpmBytes != null && rpmBytes.length == 2 && mounted) {
      setState(() => _rpm = (((rpmBytes[0] << 8) | rpmBytes[1]) ~/ 4));
    }

    final speed = _parsePid(response, '0D');
    final coolant = _parsePid(response, '05');
    final throttle = _parsePid(response, '11');
    final load = _parsePid(response, '04');
    final iat = _parsePid(response, '0F');
    final fuel = _parsePid(response, '2F');
    final map = _parsePid(response, '0B');
    final mafBytes = _parsePidBytes(response, '10', 2);
    final ambient = _parsePid(response, '46');
    final o2 = _parsePid(response, '14');
    if (mounted) {
      setState(() {
        if (speed != null) _speed = speed;
        if (coolant != null) _coolant = coolant - 40;
        if (throttle != null) _throttle = ((throttle * 100) / 255).round();
        if (load != null) _engineLoad = ((load * 100) / 255).round();
        if (iat != null) _iat = iat - 40;
        if (fuel != null) _fuelLevel = (fuel * 100.0) / 255.0;
        if (map != null) _map = map.toDouble();
        if (mafBytes != null) _maf = ((mafBytes[0] << 8) | mafBytes[1]) / 100.0;
        if (ambient != null) _ambient = ambient - 40.0;
        if (o2 != null) _o2 = o2 / 200.0;
      });
    }

    _updateDirectActuatorStatusFromObd(response);
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
      _snack('ابتدا اتصال ECU را برقرار کنید.');
      return;
    }
    _pollTimer?.cancel();
    setState(() { _loadingDtc = true; _dtcs.clear(); });
    try {
      String r;
      if (_protocolCode == '6' || _protocolCode == '7' || _protocolCode == '8' || _protocolCode == '9') {
        if (_udsRequestHeader.isEmpty) await _discoverUdsPhysicalAddress();
        r = _udsRequestHeader.isEmpty ? '' : await _udsRequest('1902FF', timeout: const Duration(seconds: 4));
        _parseUdsDtc(r);
      } else {
        r = await _sendAndWait('03', timeout: const Duration(seconds: 4), logCommand: true);
        if (r.isEmpty) _log('DTC: NO RESPONSE');
      }
    } finally {
      if (mounted) setState(() => _loadingDtc = false);
      _startPolling();
    }
  }

  void _parseUdsDtc(String response) {
    final pdu = _isoTpReassemble(response)?.payload ?? _hexBytes(response);
    if (pdu.isEmpty) return;
    if (pdu[0] == 0x7F) {
      if (pdu.length >= 3) {
        final nrc = _formatHex2(pdu[2]);
        _udsNrcs.add('19:$nrc');
        _log('UDS DTC NRC $nrc');
      }
      return;
    }
    if (pdu[0] != 0x59) return;
    final out = <String>{};
    var i = pdu.length > 2 ? 2 : 1;
    if (i < pdu.length) i += 1;
    while (i + 4 <= pdu.length) {
      final a = pdu[i], b = pdu[i + 1], c = pdu[i + 2];
      if ((a | b | c) != 0) out.add(_decodeDtc3(a, b, c));
      i += 4;
    }
    if (mounted) setState(() => _dtcs.addAll(out));
  }

  String _decodeDtc3(int a, int b, int c) {
    const prefixes = ['P', 'C', 'B', 'U'];
    final prefix = prefixes[(a >> 6) & 3];
    final code = ((a & 0x3F) << 8) | b;
    return '$prefix${code.toString().padLeft(4, '0')}'.toUpperCase();
  }

  Future<void> _clearDtc() async {
    if (!_connected) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأیید پاک‌سازی خطا'),
        content: const Text('پاک کردن DTC یک عملیات تغییردهنده است و ممکن است مانیتورهای OBD را Reset کند. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('پاک کن')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _clearingDtc = true);
    try {
      String r;
      if (_protocolCode == '6' || _protocolCode == '7' || _protocolCode == '8' || _protocolCode == '9') {
        if (_udsRequestHeader.isEmpty) await _discoverUdsPhysicalAddress();
        r = _udsRequestHeader.isEmpty ? '' : await _udsRequest('14FFFFFF', timeout: const Duration(seconds: 4));
        final positive = _udsPositive(r, '14FFFFFF');
        if (positive) _dtcs.clear();
        else _log('UDS CLEAR DTC rejected/no response');
      } else {
        r = await _sendAndWait('04', timeout: const Duration(seconds: 4), logCommand: true);
        if (r.isNotEmpty && !r.toUpperCase().contains('ERROR')) _dtcs.clear();
      }
    } finally {
      if (mounted) setState(() => _clearingDtc = false);
      _startPolling();
    }
  }

  OdometerDefinition? _findOdometerDefinition() {
    final family = _matchedEcu?.model.toUpperCase() ?? _profile.family.toUpperCase();
    final model = _matchedEcu?.model.toUpperCase() ?? _profile.model.toUpperCase();
    for (final d in verifiedOdometerDefinitions) {
      if (family.contains(d.ecuFamily.toUpperCase()) || model.contains(d.ecuFamily.toUpperCase())) return d;
    }
    return null;
  }

  Future<void> _readOdometer() async {
    if (!_connected) {
      _snack('ابتدا اتصال به دانگل و ECU را برقرار کنید.');
      return;
    }

    _pollTimer?.cancel();
    setState(() => _odometerStatus = 'در حال استعلام کارکرد از ECU...');

    try {
      final def = _findOdometerDefinition();

      if (def != null && def.protocol == DiagnosticProtocol.udsCan) {
        if (_protocolCode == '6' || _protocolCode == '7' || _protocolCode == '8' || _protocolCode == '9') {
          await _sendAndWait('ATCAF1');
          await _sendAndWait('ATCFC1');
          if (_udsRequestHeader.isNotEmpty) {
            await _sendAndWait('ATSH $_udsRequestHeader', timeout: const Duration(milliseconds: 700));
          } else if (_profile.header != null) {
            await _sendAndWait(_profile.header!);
          }

          if (def.sessionHex.isNotEmpty) {
            final sr = await _udsRequest(def.sessionHex);
            if (!_udsPositive(sr, def.sessionHex)) throw Exception('عدم پذیرش سشن عیب‌یابی');
          }

          final r = await _udsRequest('${def.serviceHex}${def.didHex}', timeout: const Duration(seconds: 3));
          final payload = _isoTpReassemble(r)?.payload ?? _hexBytes(r);
          final value = _decodeDefinitionValue(payload, def);

          if (value != null && value > 0) {
            setState(() {
              _supportsOdometer = true;
              _odometer = value;
              _odometerStatus = '${value.toStringAsFixed(0)} ${def.unit}';
            });
            _log('ODOMETER OK (${def.id}): ${_odometer.toStringAsFixed(0)} ${def.unit}');
            return;
          }
        }
      }

      final obdResp = await _sendAndWait('01A6', timeout: const Duration(seconds: 3), logCommand: true);
      final obdBytes = _parsePidBytes(obdResp, 'A6', 4);
      if (obdBytes != null && obdBytes.length == 4) {
        final rawVal = ((obdBytes[0] << 24) | (obdBytes[1] << 16) | (obdBytes[2] << 8) | obdBytes[3]);
        final km = rawVal / 10.0;
        setState(() {
          _supportsOdometer = true;
          _odometer = km;
          _odometerStatus = '${km.toStringAsFixed(0)} KM';
        });
        _log('ODOMETER OK (OBD-II 01A6): ${km.toStringAsFixed(0)} KM');
        return;
      }

      setState(() {
        _supportsOdometer = false;
        _odometer = 0;
        _odometerStatus = 'این ECU دسترسی مستقیم به کیلومتر را ارائه نمی‌دهد';
      });
      _log('ODOMETER: NOT SUPPORTED BY ECU');
    } catch (e) {
      setState(() {
        _supportsOdometer = false;
        _odometerStatus = 'خطا در خواندن: ${e.toString().replaceAll('Exception: ', '')}';
      });
      _log('ODOMETER ERROR: $e');
    } finally {
      _startPolling();
    }
  }

  double? _decodeDefinitionValue(List<int> payload, OdometerDefinition def) {
    if (def.dataLength <= 0 || def.dataOffset < 0 || payload.length < def.dataOffset + def.dataLength) return null;
    final data = payload.sublist(def.dataOffset, def.dataOffset + def.dataLength);
    int value = 0;
    if (def.bigEndian) {
      for (final b in data) {
        value = (value << 8) | b;
      }
    } else {
      for (int i = data.length - 1; i >= 0; i--) {
        value = (value << 8) | data[i];
      }
    }
    return value * def.scale + def.offset;
  }

  Future<String> _udsRequest(String payloadHex, {Duration timeout = const Duration(seconds: 4)}) async {
    if(!_connected || _connection==null) return '';

    final request=payloadHex.replaceAll(RegExp(r'\s+'),'').toUpperCase();
    if(request.length<2) return '';

    final bytes=_hexBytes(request);
    if(bytes.isEmpty) return '';

    final service=bytes.first;
    final key='UDS$service:$request';

    final existing=_waiters[key];
    if(existing!=null) return existing.future;

    final c=Completer<String>();
    _waiters[key]=c;

    _log('UDS TX $request${_udsRequestHeader.isEmpty ? '' : ' @ $_udsRequestHeader'}');

    try{
      if (_udsRequestHeader.isNotEmpty) {
        await _sendAndWait('ATSH $_udsRequestHeader', timeout: const Duration(milliseconds: 700));
      }
      _connection!.output.add(Uint8List.fromList(utf8.encode('$request\r')));
      await _connection!.output.allSent;

      final response=await c.future.timeout(
        timeout,
        onTimeout:()=> '',
      );

      if(response.isEmpty){
        _log('UDS TIMEOUT $request');
      }else{
        final pdu=_isoTpReassemble(response)?.payload;
        _log('UDS RX ${pdu==null ? response : pdu.map((e)=>e.toRadixString(16).padLeft(2,'0')).join().toUpperCase()}');
      }

      return response;
    }finally{
      if(identical(_waiters[key],c))_waiters.remove(key);
    }
  }

  bool _udsPositive(String response,String requestHex){
    final pdu=_isoTpReassemble(response)?.payload ?? _hexBytes(response);
    final req=_hexBytes(requestHex);
    if(pdu.isEmpty||req.isEmpty)return false;

    if(pdu[0]==((req[0]+0x40)&0xFF))return true;

    if(pdu[0]==0x7F && pdu.length>=3){
      _log('UDS NRC ${pdu[1].toRadixString(16).padLeft(2,'0').toUpperCase()}');
    }
    return false;
  }

  Future<String> _udsReadDid(int did) async {
    final request='22${did.toRadixString(16).padLeft(4,'0').toUpperCase()}';
    return _udsRequest(request);
  }

  String _decodeUdsVin(String response){
    final pdu=_isoTpReassemble(response)?.payload ?? _hexBytes(response);
    if(pdu.length<3 || pdu[0]!=0x62 || pdu[1]!=0xF1 || pdu[2]!=0x90)return '';

    return String.fromCharCodes(
      pdu.sublist(3).where((b)=>b>=0x20&&b<=0x7E),
    ).trim();
  }

  Future<void> _discoverSupportedPids() async {
    if (!_connected || _protocolCode == 'A') return;
    final found = <String>{};
    for (final pid in const ['00','20','40','60','80','A0']) {
      final r = await _sendAndWait('01$pid', timeout: const Duration(milliseconds: 1200));
      final clean = r.replaceAll(RegExp(r'\s+'),'').toUpperCase();
      final marker = '41$pid';
      final idx = clean.indexOf(marker);
      if (idx >= 0 && idx + 10 <= clean.length) {
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
    _supportedPids
      ..clear()
      ..addAll(found);
    _log('SUPPORTED PIDs: ${found.isEmpty ? 'none detected' : found.join(',')}');
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (!_connected || false) return;
    _pollIndex = 0;
    final base = <String>['0C','0D','05','11','04','0F','2F','14','0B','10','46'];
    final commands = _supportedPids.isEmpty ? base.map((p) => '01$p').toList() : base.where((p) => _supportedPids.contains(p)).map((p) => '01$p').toList();
    commands.add('ATRV');
    if (_protocolCode == 'A') {
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (!_connected || _requestInFlight) return;
        _requestInFlight = true;
        try { await _sendAndWait('ATMP FECA 1', timeout: const Duration(seconds: 3)); }
        finally { _requestInFlight = false; }
      });
      return;
    }
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_connected || _requestInFlight || _activeRunningTest != null) return;
      _requestInFlight = true;
      try {
        final cmd = commands[_pollIndex % commands.length];
        _pollIndex++;
        await _sendAndWait(cmd, timeout: const Duration(milliseconds: 900));
      } finally {
        _requestInFlight = false;
      }
    });
  }

  void _toggleDemo(bool enable) {
    _demoTimer?.cancel();
    _pollTimer?.cancel();
    if (enable && _connected) _disconnect();
    setState(() => _demo = enable);
    if (!enable) return;
    final r = Random();
    _demoTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted) return;
      setState(() {
        _speed = (_speed + r.nextInt(7) - 3).clamp(0, 180).toInt();
        _rpm = (_speed * 30 + 850 + r.nextInt(250)).clamp(800, 6500).toInt();
        _coolant = 88 + r.nextInt(5);
        _throttle = (_speed / 2.0).round().clamp(0, 100).toInt();
        _engineLoad = (15 + _speed / 2.5).round().clamp(15, 95).toInt();
        _iat = 30;
        _fuelLevel = 35 + r.nextDouble() * 50;
        _map = 35 + r.nextDouble() * 25;
        _maf = 3 + r.nextDouble() * 12;
        _ambient = 22 + r.nextDouble() * 8;
        _voltage = 13.8 + r.nextDouble() * .3;
        _o2 = .35 + r.nextDouble() * .45;
        _ecuModel = 'DEMO ECU';
        _protocol = 'DEMO';
      });
    });
  }

  bool _isActuatorSupportedForCurrentEcu(ActuatorTestDefinition test) {
    if (_matchedEcu == null) return false;
    return test.supportedEcuFamilies.contains(_matchedEcu!.id);
  }

  Future<void> _runActuatorTest(ActuatorTestDefinition test) async {
    if (!_connected) {
      _snack('ابتدا اتصال به ECU را برقرار کنید.');
      return;
    }

    if (_rpm > 0) {
      _snack('خطای ایمنی: تست عملگر تنها با موتور خاموش و سوئیچ باز مجاز است.');
      return;
    }

    if (_speed > 0) {
      _snack('خطای ایمنی: سرعت خودرو صفر نیست.');
      return;
    }

    if (_activeRunningTest != null) {
      await _stopCurrentActuatorTest();
    }

    setState(() {
      _actuatorActionInProgress = true;
      _activeRunningTest = test;
      _actuatorRemainingSeconds = test.autoStopSeconds;
    });

    _pollTimer?.cancel();

    try {
      if (test.protocol == ActuatorProtocolType.uds) {
        final sessionResp = await _udsRequest('1003', timeout: const Duration(seconds: 2));
        if (!_udsPositive(sessionResp, '1003')) {
          throw Exception('ECU اجازه ورود به Extended Session ($sessionResp) را نداد.');
        }

        final testResp = await _udsRequest(test.startHex, timeout: const Duration(seconds: 3));
        if (!_udsPositive(testResp, test.startHex)) {
          throw Exception('فرمان فعال‌سازی رد شد: $testResp');
        }
      } else {
        final r = await _sendAndWait(test.startHex, timeout: const Duration(seconds: 3), logCommand: true);
        if (r.isEmpty || r.contains('7F')) {
          throw Exception('پاسخ منفی در پروتکل KWP: $r');
        }
      }

      _log('ACTUATOR TEST STARTED: ${test.name}');
      _snack('تست ${test.name} آغاز شد.');

      _actuatorCountdownTimer?.cancel();
      _actuatorCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
        if (_actuatorRemainingSeconds <= 1) {
          timer.cancel();
          await _stopCurrentActuatorTest();
        } else {
          if (mounted) {
            setState(() => _actuatorRemainingSeconds--);
          }
        }
      });
    } catch (e) {
      _log('ACTUATOR ERROR: $e');
      _snack('خطا در اجرای تست: $e');
      await _stopCurrentActuatorTest();
    } finally {
      if (mounted) setState(() => _actuatorActionInProgress = false);
    }
  }

  Future<void> _stopCurrentActuatorTest() async {
    _actuatorCountdownTimer?.cancel();
    _actuatorCountdownTimer = null;

    final test = _activeRunningTest;
    if (test != null && _connected) {
      try {
        if (test.protocol == ActuatorProtocolType.uds) {
          await _udsRequest(test.stopHex, timeout: const Duration(seconds: 2));
          await _udsRequest('1001', timeout: const Duration(milliseconds: 800));
        } else {
          await _sendAndWait(test.stopHex, timeout: const Duration(seconds: 2));
        }
        _log('ACTUATOR TEST STOPPED: ${test.name}');
      } catch (e) {
        _log('ERROR STOPPING ACTUATOR: $e');
      }
    }

    if (mounted) {
      setState(() {
        _activeRunningTest = null;
        _actuatorRemainingSeconds = 0;
      });
    }
    _startPolling();
  }

  Future<void> _disconnect() async {
    _actuatorCountdownTimer?.cancel();
    _activeRunningTest = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    await _serialSub?.cancel();
    _serialSub = null;
    try { await _connection?.finish(); } catch (_) {}
    try { _connection?.dispose(); } catch (_) {}
    _connection = null;
    if (mounted) {
      setState(() {
        _connected = false;
        _connecting = false;
        _connectionStatus = 'آماده اتصال';
        _udsRequestHeader = '';
        _udsResponseHeader = '';
        _discoveryMethod = '---';
        _actuatorStates.clear();
        _actuatorChangedAt.clear();
        _actuatorChangeText.clear();
        _actuatorEvidence.clear();
      });
    }
  }

  void _snack(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  void dispose() {
    _actuatorCountdownTimer?.cancel();
    _demoTimer?.cancel();
    _pollTimer?.cancel();
    _serialSub?.cancel();
    _connection?.dispose();
    _tabs.dispose();
    _terminalController.dispose();
    _supportSessionCodeController.dispose();
    _workshopController.dispose();
    _technicianController.dispose();
    _phoneController.dispose();
    _remoteClose();
    super.dispose();
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

  // --- سیستم ریموت ساده‌شده بر پایه کد ۶ رقمی ---
  Future<void> _startCustomerSession() async {
    if (!_connected) {
      _snack('ابتدا دانگل بلوتوث را به خودرو متصل کنید.');
      return;
    }
    await _remoteClose();
    _customerSessionCode = _newSixDigitCode();
    _remoteRoleLabel = 'مشتری (متصل به خودرو)';

    setState(() => _remoteConnecting = true);
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

      _snack('کد ۶ رقمی ساخته شد. آن را برای پشتیبان ارسال کنید.');
    } catch (e) {
      _remoteStatus = 'خطا در اتصال به سرور: $e';
    } finally {
      if (mounted) setState(() => _remoteConnecting = false);
    }
  }

  Future<void> _connectAsExpert() async {
    final code = _supportSessionCodeController.text.trim();
    if (code.length != 6) {
      _snack('لطفاً کد ۶ رقمی مشتری را دقیق وارد کنید.');
      return;
    }
    await _remoteClose();
    _remoteRoleLabel = 'پشتیبان فنی';

    setState(() => _remoteConnecting = true);
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
      _remoteStatus = 'متصل به خودروی مشتری ($code)';

      _remoteSub = ws.listen((data) => _handleRemoteMessage(data.toString()), onDone: () {
        if (mounted) setState(() { _remoteConnected = false; _remoteStatus = 'قطع ارتباط'; });
      }, onError: (_) {
        if (mounted) setState(() { _remoteConnected = false; _remoteStatus = 'خطای ارتباطی'; });
      });

      ws.add(jsonEncode({'type': 'join_expert', 'target_code': code}));
      _remoteHeartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_remoteConnected) _remoteSocket?.add(jsonEncode({'type': 'ping'}));
      });

      _snack('با موفقیت به دیاگ مشتری متصل شدید!');
    } catch (e) {
      _remoteStatus = 'عدم اتصال به مشتری: $e';
    } finally {
      if (mounted) setState(() => _remoteConnecting = false);
    }
  }

  void _sendRemoteDiagnostic(String cmd) {
    if (!_remoteConnected) {
      _snack('ارتباط با سرور یا دیاگ مشتری متصل نیست.');
      return;
    }
    _remoteSend({'type': 'diagnostic_request', 'command': cmd});
    _log('REMOTE SENT → $cmd');
  }

  void _handleRemoteMessage(String raw){
    try{
      final m=jsonDecode(raw); if(m is! Map)return;
      if(m['type']=='pong')return;
      if(m['type']=='terminal' && m['data'] is String){_log('REMOTE ← ${m['data']}'); return;}
      if(m['type']=='diagnostic_result'){
        final ok=m['ok']==true;
        final command='${m['command']??''}';
        final response='${m['response']??m['error']??''}';
        _log('REMOTE RESULT [$command] $response');
        if(mounted)setState((){
          if(_remoteResults.length>=80)_remoteResults.removeAt(0);
          _remoteResults.add('${ok ? '✓' : '✗'}  $command\n$response');
        });
        return;
      }
      if(m['type']=='diagnostic_request' && m['command'] is String){
        if(!_connected){_remoteSend({'type':'diagnostic_result','ok':false,'error':'ECU disconnected'});return;}
        _sendAndWait(m['command'].toString(),timeout:const Duration(seconds:3)).then((r)=>_remoteSend({'type':'diagnostic_result','ok':true,'command':m['command'],'response':r})).catchError((e)=>_remoteSend({'type':'diagnostic_result','ok':false,'error':'$e'}));
      }
      if(m['type']=='notice')_snack('${m['message']??''}');
    }catch(_){_log('REMOTE ← $raw');}
  }

  void _remoteSend(Map<String,dynamic> message){if(_remoteConnected)_remoteSocket?.add(jsonEncode(message));}

  Future<void> _remoteClose() async {
    _remoteHeartbeat?.cancel(); _remoteHeartbeat=null;
    await _remoteSub?.cancel(); _remoteSub=null;
    try{await _remoteSocket?.close();}catch(_){ }
    _remoteSocket=null; _remoteConnected=false;
  }

  Widget _remoteTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Card(
          color: _remoteConnected ? const Color(0xFF0C241B) : const Color(0xFF10141E),
          child: ListTile(
            leading: Icon(
              _remoteConnected ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
              color: _remoteConnected ? const Color(0xFF00E676) : Colors.white38,
              size: 32,
            ),
            title: Text(
              _remoteConnected ? 'اتصال ریموت فعال است' : 'مرکز پشتیبانی از راه دور',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text('وضعیت: $_remoteStatus • نقش: $_remoteRoleLabel'),
            trailing: _remoteConnected
                ? OutlinedButton(
                    onPressed: () { _remoteClose(); setState(() {}); },
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF2A55)),
                    child: const Text('قطع'),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.directions_car_filled_rounded, color: Color(0xFF00F0FF)),
                    SizedBox(width: 8),
                    Text('من پیش خودرو هستم (دریافت کمک)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('اگر در محل خودرو هستید، کلید زیر را بزنید و کد ظاهر شده را برای کارشناس پشتیبان بخوانید:',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 14),
                if (_customerSessionCode.isNotEmpty && _remoteConnected) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A1F18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF00E676), width: 1.5),
                    ),
                    child: Column(
                      children: [
                        const Text('کد اتصال شما:', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        const SizedBox(height: 4),
                        SelectableText(
                          _customerSessionCode,
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF00E676), letterSpacing: 8),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                FilledButton.icon(
                  onPressed: _remoteConnecting || (_remoteConnected && _remoteRoleLabel.contains('مشتری'))
                      ? null
                      : _startCustomerSession,
                  icon: const Icon(Icons.share_location_rounded),
                  label: Text(_remoteConnecting ? 'در حال اتصال...' : 'دریافت کد اتصال ۶ رقمی'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.support_agent_rounded, color: Color(0xFFFFD54F)),
                    SizedBox(width: 8),
                    Text('من پشتیبان هستم (اتصال به خودروی مشتری)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _supportSessionCodeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.w900),
                  decoration: const InputDecoration(
                    labelText: 'کد ۶ رقمی مشتری را اینجا وارد کنید',
                    hintText: 'مثلاً 482910',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _remoteConnecting || (_remoteConnected && _remoteRoleLabel.contains('پشتیبان'))
                      ? null
                      : _connectAsExpert,
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFD54F), foregroundColor: Colors.black),
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('اتصال مستقیم به خودرو'),
                ),
                if (_remoteConnected && _remoteRoleLabel.contains('پشتیبان')) ...[
                  const Divider(height: 28),
                  const Text('میز کار کنترل از راه دور:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.search, size: 18),
                        label: const Text('خواندن خطا (DTC)'),
                        onPressed: () => _sendRemoteDiagnostic('03'),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.delete_sweep, size: 18),
                        label: const Text('پاک‌سازی خطاها'),
                        onPressed: () => _sendRemoteDiagnostic('04'),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.fingerprint, size: 18),
                        label: const Text('شماره VIN'),
                        onPressed: () => _sendRemoteDiagnostic('0902'),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.speed, size: 18),
                        label: const Text('دور موتور لحظه‌ای'),
                        onPressed: () => _sendRemoteDiagnostic('010C'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _terminalController,
                          decoration: const InputDecoration(hintText: 'کد دلخواه (مثلاً 0105 یا 22F190)', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          final c = _terminalController.text.trim();
                          if (c.isNotEmpty) {
                            _sendRemoteDiagnostic(c);
                            _terminalController.clear();
                          }
                        },
                        icon: const Icon(Icons.send_rounded, color: Color(0xFF00F0FF)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_remoteResults.isNotEmpty) ...[
                    const Text('نتایج دریافتی از خودرو:', style: TextStyle(fontSize: 12, color: Colors.white60)),
                    const SizedBox(height: 6),
                    ..._remoteResults.reversed.take(6).map((res) => Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                          child: Text(res, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF00F0FF))),
                        )),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _customTab()=>ListView(padding:const EdgeInsets.all(14),children:[
    Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('شخصی‌سازی حرفه‌ای',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),const SizedBox(height:12),
      TextField(controller:_workshopController,decoration:const InputDecoration(labelText:'نام تعمیرگاه / مجموعه')),
      const SizedBox(height:8),TextField(controller:_technicianController,decoration:const InputDecoration(labelText:'نام تکنسین')),
      const SizedBox(height:8),TextField(controller:_phoneController,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'شماره تماس')),
      const SizedBox(height:12),const Text('رنگ اصلی'),const SizedBox(height:8),
      Wrap(spacing:8,children:[0xFF00F0FF,0xFF00E676,0xFFFFC107,0xFFFF4081,0xFF7C4DFF,0xFF42A5F5].map((v)=>GestureDetector(onTap:(){setState(()=>_accent=Color(v));},child:CircleAvatar(backgroundColor:Color(v),child:_accent.value==v?const Icon(Icons.check,color:Colors.black):null))).toList()),
      const SizedBox(height:14),FilledButton.icon(onPressed:_saveCustomization,icon:const Icon(Icons.save),label:const Text('ذخیره شخصی‌سازی')),
    ]))),
    Card(child:ListTile(leading:Icon(Icons.badge,color:_accent),title:Text(_custom.workshopName.isEmpty?'RASA DIAG PRO':_custom.workshopName),subtitle:Text('${_custom.technicianName}  ${_custom.phone}'))),
  ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_custom.workshopName.isEmpty ? 'RASA DIAG PRO' : _custom.workshopName, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(onPressed: _identifyVehicle, icon: const Icon(Icons.manage_search_rounded), tooltip: 'شناسایی ECU'),
          IconButton(onPressed: _selectBluetoothDevice, icon: const Icon(Icons.bluetooth_connected_rounded), tooltip: 'اتصال'),
          PopupMenuButton<String>(
            onSelected: (v) { if (v == 'demo') _toggleDemo(!_demo); if (v == 'disconnect') _disconnect(); },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'demo', child: Text(_demo ? 'خاموش کردن دمو' : 'حالت دمو')),
              const PopupMenuItem(value: 'disconnect', child: Text('قطع اتصال')),
            ],
          ),
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
            Tab(icon: Icon(Icons.cloud_sync_rounded), text: 'ریموت'),
            Tab(icon: Icon(Icons.tune_rounded), text: 'شخصی‌سازی'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _dashboard(), _vehicleTab(), _sensorsTab(), _dtcTab(), _actuatorTab(), _ecuTab(), _terminalTab(), _remoteTab(), _customTab(),
      ]),
    );
  }

  Widget _dashboard() => ListView(padding: const EdgeInsets.all(14), children: [
        _statusCard(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: RasaGauge(label: 'دور موتور', value: '$_rpm', unit: 'RPM', progress: (_rpm / 7000).clamp(0.0, 1.0).toDouble())),
          const SizedBox(width: 10),
          Expanded(child: RasaGauge(label: 'سرعت', value: '$_speed', unit: 'KM/H', progress: (_speed / 240).clamp(0.0, 1.0).toDouble())),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _metric('دمای آب', '$_coolant °C', Icons.thermostat)),
          const SizedBox(width: 8), Expanded(child: _metric('دریچه گاز', '$_throttle %', Icons.shutter_speed)),
          const SizedBox(width: 8), Expanded(child: _metric('ولتاژ', '${_voltage.toStringAsFixed(1)} V', Icons.bolt)),
        ]),
        const SizedBox(height: 10),
        Card(child: ListTile(
          leading: const Icon(Icons.local_gas_station_rounded, color: Color(0xFFFFD54F), size: 32),
          title: const Text('سوخت موجود در باک'),
          subtitle: Text(_fuelLevel >= 0 ? 'سطح سوخت استاندارد OBD-II • ${_fuelLevel.toStringAsFixed(0)}٪' : 'این ECU PID 2F را ارائه نمی‌کند'),
          trailing: _fuelLevel >= 0 ? SizedBox(width: 90, child: LinearProgressIndicator(value: (_fuelLevel / 100).clamp(0.0, 1.0).toDouble())) : const Icon(Icons.help_outline),
        )),
        const SizedBox(height: 12),
        _ecuMiniCard(),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFF10141E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: _supportsOdometer ? const Color(0xFF00F0FF).withOpacity(0.4) : Colors.white10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF00F0FF).withOpacity(0.12),
                  child: const Icon(Icons.add_road_rounded, color: Color(0xFF00F0FF), size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('کارکرد واقعی خودرو (Odometer)', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(height: 3),
                      Text(
                        _supportsOdometer ? '${_odometer.toStringAsFixed(0)} کیلومتر' : _odometerStatus,
                        style: TextStyle(
                          fontSize: _supportsOdometer ? 18 : 13,
                          fontWeight: FontWeight.w900,
                          color: _supportsOdometer ? const Color(0xFF00E676) : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _connected ? _readOdometer : null,
                  child: const Text('استعلام'),
                ),
              ],
            ),
          ),
        ),
      ]);

  Widget _statusCard() => Card(
        child: ListTile(
          leading: Icon(_connected ? Icons.check_circle : Icons.link_off, color: _connected ? const Color(0xFF00E676) : const Color(0xFFFF2A55), size: 30),
          title: Text(_connectionStatus, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('Protocol: $_protocol\nAdapter: $_adapterInfo'),
          trailing: _demo ? const Chip(label: Text('DEMO')) : null,
        ),
      );

  Widget _ecuMiniCard() => Card(
        child: ListTile(
          leading: const CircleAvatar(backgroundColor: Color(0xFF18212C), child: Icon(Icons.memory_rounded, color: Color(0xFF00F0FF))),
          title: const Text('ECU شناسایی‌شده', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(_ecuModel),
          trailing: IconButton(onPressed: _identifyVehicle, icon: const Icon(Icons.refresh_rounded)),
        ),
      );

  Widget _metric(String title, String value, IconData icon) => Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(children: [Icon(icon, color: const Color(0xFF00F0FF)), const SizedBox(height: 5), Text(title, style: const TextStyle(fontSize: 10, color: Colors.white54)), const SizedBox(height: 3), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))])));

  Widget _vehicleTab() => ListView(padding: const EdgeInsets.all(14), children: [
        Card(child: ListTile(
          leading: const Icon(Icons.hub_rounded, color: Color(0xFF00F0FF)),
          title: const Text('اسکن تمام پروتکل‌های ارتباطی'),
          subtitle: Text(_protocolScanRunning ? 'در حال اسکن...' : '$_protocol • Code $_protocolCode'),
          trailing: FilledButton(onPressed: _connected && !_protocolScanRunning ? _scanAllElmProtocols : null, child: const Text('SCAN')),
        )),
        Card(child: ListTile(
          leading: const Icon(Icons.storage_rounded, color: Color(0xFFFFD600)),
          title: const Text('بانک واقعی ECU — RASA ECU Database'),
          subtitle: Text(_databaseScanning ? 'در حال Discovery...' : _databaseStatus),
          trailing: FilledButton.icon(onPressed: _connected && !_databaseScanning ? _discoverEcuDatabase : null, icon: const Icon(Icons.manage_search), label: const Text('DISCOVER')),
        )),
        if (_matchedEcu != null) Card(child: ListTile(
          leading: const Icon(Icons.verified_rounded, color: Color(0xFF00E676)),
          title: Text(_matchedEcu!.title),
          subtitle: Text('${_matchedEcu!.vehicleFamily} • ${_matchedEcu!.model}\n${_matchedEcu!.protocolName} • ${_matchedEcu!.confidenceText}'),
          isThreeLine: true,
          trailing: IconButton(onPressed: _saveDiscoverySnapshot, icon: const Icon(Icons.save_alt_rounded)),
        )),
        const SizedBox(height: 8),
        const Text('پروفایل‌های عمومی / Legacy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...ecuProfiles.map((p) => Card(
              child: ListTile(
                leading: Icon(p.protocol.contains('CAN') || p.protocol.contains('UDS') ? Icons.account_tree_rounded : Icons.memory_rounded, color: const Color(0xFF00F0FF)),
                title: Text(p.title),
                subtitle: Text('${p.family}\n${p.protocol}${p.header == null ? '' : ' • ${p.header}'}'),
                isThreeLine: true,
                trailing: p == _profile ? const Icon(Icons.check_circle, color: Color(0xFF00E676)) : null,
                onTap: () => _applyProfile(p),
              ),
            )),
      ]);

  Widget _sensorsTab() => ListView(padding: const EdgeInsets.all(14), children: [
        _sensor('RPM', '$_rpm RPM', Icons.speed),
        _sensor('سرعت خودرو', '$_speed km/h', Icons.directions_car),
        _sensor('دمای آب', '$_coolant °C', Icons.thermostat),
        _sensor('دریچه گاز', '$_throttle %', Icons.shutter_speed),
        _sensor('لود موتور', '$_engineLoad %', Icons.compress),
        _sensor('دمای هوای ورودی', '$_iat °C', Icons.air),
        _sensor('سنسور O2', '${_o2.toStringAsFixed(3)} V', Icons.air_rounded),
        _sensor('ولتاژ سیستم', '${_voltage.toStringAsFixed(2)} V', Icons.bolt),
        _sensor('سوخت موجود', _fuelLevel >= 0 ? '${_fuelLevel.toStringAsFixed(0)} %' : 'پشتیبانی نشده', Icons.local_gas_station_rounded),
        _sensor('فشار منیفولد', _map >= 0 ? '${_map.toStringAsFixed(0)} kPa' : '---', Icons.compress_rounded),
        _sensor('جرم هوای ورودی', _maf >= 0 ? '${_maf.toStringAsFixed(1)} g/s' : '---', Icons.air_rounded),
        _sensor('دمای محیط', _ambient > -99 ? '${_ambient.toStringAsFixed(0)} °C' : '---', Icons.thermostat_auto_rounded),
        _sensor('کارکرد', _supportsOdometer ? '${_odometer.toStringAsFixed(0)} KM' : _odometerStatus, Icons.add_road),
      ]);

  Widget _sensor(String n, String v, IconData i) => Card(child: ListTile(leading: Icon(i, color: const Color(0xFF00F0FF)), title: Text(n), trailing: Text(v, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00F0FF)))));

  Widget _dtcTab() => Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          Expanded(child: FilledButton.icon(onPressed: _loadingDtc ? null : _scanDtc, icon: const Icon(Icons.search), label: const Text('اسکن DTC'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton.icon(onPressed: _clearingDtc ? null : _clearDtc, style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF2A55)), icon: const Icon(Icons.delete_sweep), label: const Text('پاک‌سازی'))),
        ])),
        if (_loadingDtc) const LinearProgressIndicator(),
        Expanded(child: _dtcs.isEmpty ? const Center(child: Text('خطایی در حافظه نمایش داده نشده است.')) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: _dtcs.length, itemBuilder: (_, i) {
          final c = _dtcs[i];
          return Card(child: ListTile(leading: Text(c, style: const TextStyle(color: Color(0xFFFF2A55), fontWeight: FontWeight.bold)), title: Text(dtcDescriptions[c] ?? 'شرح کارخانه‌ای / Manufacturer Specific')));
        })),
      ]);

  static const List<_ActuatorStatusDefinition> _actuatorStatusDefinitions = [
    _ActuatorStatusDefinition(name: 'انژکتور 1', group: 'سوخت', icon: Icons.water_drop_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'انژکتور 2', group: 'سوخت', icon: Icons.water_drop_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'انژکتور 3', group: 'سوخت', icon: Icons.water_drop_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'انژکتور 4', group: 'سوخت', icon: Icons.water_drop_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'پمپ بنزین', group: 'سوخت', icon: Icons.local_gas_station_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'رله اصلی / رله دوبل', group: 'برق ECU', icon: Icons.electrical_services_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'کویل 1/4', group: 'جرقه', icon: Icons.bolt_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'کویل 2/3', group: 'جرقه', icon: Icons.bolt_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'فن دور کند', group: 'خنک کاری', icon: Icons.air_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'فن دور تند', group: 'خنک کاری', icon: Icons.air_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'پمپ آب برقی', group: 'خنک کاری', icon: Icons.water_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'دریچه گاز برقی', group: 'هوا', icon: Icons.tune_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'استپر / کنترل دور آرام', group: 'هوا', icon: Icons.settings_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'شیر EGR', group: 'هوا', icon: Icons.air_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'شیر کنیستر EVAP', group: 'هوا', icon: Icons.filter_alt_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'VVT / CVVT', group: 'تایمینگ', icon: Icons.settings_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'شیر Wastegate / Boost', group: 'توربو', icon: Icons.speed_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'کمپرسور کولر', group: 'کولر', icon: Icons.ac_unit_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'گرمکن سنسور اکسیژن', group: 'اگزوز', icon: Icons.whatshot_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'پمپ هوای ثانویه', group: 'اگزوز', icon: Icons.air_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'رگلاتور فشار سوخت', group: 'سوخت', icon: Icons.compress_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'شمع گرمکن', group: 'جرقه', icon: Icons.local_fire_department_rounded, source: _ActuatorSourceType.unavailable),
    _ActuatorStatusDefinition(name: 'چراغ MIL', group: 'هشدار', icon: Icons.warning_amber_rounded, source: _ActuatorSourceType.obdPid, idHex: '01', byteOffset: 0, mask: 0x80, onValue: 0x80, offValue: 0x00),
  ];

  List<_ActuatorStatusDefinition> get _availableActuatorDefinitions => _actuatorStatusDefinitions;

  String _statusSourceLabel(_ActuatorSourceType source) {
    switch (source) {
      case _ActuatorSourceType.obdPid: return 'OBD-II مستقیم';
      case _ActuatorSourceType.udsDid: return 'UDS DID مستقیم';
      case _ActuatorSourceType.unavailable: return 'منبع مستقیم ثبت نشده';
    }
  }

  void _recordDirectActuatorState(String name, String state, String evidence) {
    final old = _actuatorStates[name];
    if (old != state) {
      _actuatorChangedAt[name] = DateTime.now();
      _actuatorChangeText[name] = old == null ? 'اولین وضعیت قطعی ثبت شد' : '$old ← $state';
    }
    _actuatorStates[name] = state;
    _actuatorEvidence[name] = evidence;
  }

  void _updateDirectActuatorStatusFromObd(String response) {
    final clean = response.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final milIdx = clean.indexOf('4101');
    if (milIdx >= 0 && milIdx + 6 <= clean.length) {
      final v = int.tryParse(clean.substring(milIdx + 4, milIdx + 6), radix: 16);
      if (v != null) {
        final state = (v & 0x80) != 0 ? 'ON — قطعی' : 'OFF — قطعی';
        _recordDirectActuatorState('چراغ MIL', state, 'OBD PID 01 • MIL bit7 • raw=${v.toRadixString(16).padLeft(2, '0').toUpperCase()}');
        if (mounted) setState(() {});
      }
    }

    final idx = clean.indexOf('4103');
    if (idx >= 0 && idx + 8 <= clean.length) {
      final a = int.tryParse(clean.substring(idx + 4, idx + 6), radix: 16);
      final b = int.tryParse(clean.substring(idx + 6, idx + 8), radix: 16);
      if (a != null) {
        String state;
        if (a == 0) state = 'OFF — قطعی';
        else if ((a & 0x02) != 0) state = 'CLOSED LOOP — قطعی';
        else if ((a & 0x01) != 0) state = 'OPEN LOOP — قطعی';
        else state = 'STATUS — قطعی';
        _recordDirectActuatorState('وضعیت سیستم سوخت 1', state,
            'OBD PID 03 • byte=${a.toRadixString(16).padLeft(2, '0').toUpperCase()}${b == null ? '' : ' ${b.toRadixString(16).padLeft(2, '0').toUpperCase()}'}');
        if (mounted) setState(() {});
      }
    }

    final airIdx = clean.indexOf('4112');
    if (airIdx >= 0 && airIdx + 6 <= clean.length) {
      final v = int.tryParse(clean.substring(airIdx + 4, airIdx + 6), radix: 16);
      if (v != null) {
        final state = v == 0 ? 'OFF — قطعی' : 'ON — قطعی';
        _recordDirectActuatorState('پمپ هوای ثانویه', state, 'OBD PID 12 • raw=${v.toRadixString(16).padLeft(2, '0').toUpperCase()}');
        if (mounted) setState(() {});
      }
    }
  }

  Widget _actuatorStatusCard(_ActuatorStatusDefinition def) {
    final state = _actuatorStates[def.name] ?? 'NOT SUPPORTED';
    final evidence = _actuatorEvidence[def.name] ?? _statusSourceLabel(def.source);
    final changed = _actuatorChangedAt[def.name];
    final change = _actuatorChangeText[def.name];
    final direct = state.contains('قطعی');
    final color = direct ? (state.startsWith('ON') || state.startsWith('CLOSED') ? const Color(0xFF00E676) : const Color(0xFFB0BEC5)) : const Color(0xFFFFC107);
    return Card(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        CircleAvatar(radius: 22, backgroundColor: color.withOpacity(.12), child: Icon(def.icon, color: color)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(def.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(def.group, style: const TextStyle(fontSize: 10, color: Colors.white38)),
          const SizedBox(height: 3),
          Text(evidence, style: const TextStyle(fontSize: 11, color: Colors.white60)),
          if (changed != null && change != null) Text('تغییر: $change', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(state, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
          if (changed != null) Text('${changed.hour.toString().padLeft(2,'0')}:${changed.minute.toString().padLeft(2,'0')}:${changed.second.toString().padLeft(2,'0')}', style: const TextStyle(fontSize: 10, color: Colors.white38)),
        ]),
      ]),
    ));
  }

  Widget _actuatorTab() {
    return ListView(padding: const EdgeInsets.all(14), children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.verified_user_rounded, color: Color(0xFF00F0FF), size: 32),
          title: const Text('تست و فعال‌سازی عملگرها (Actuator Test)', style: TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(_matchedEcu != null ? 'تطبیق با: ${_matchedEcu!.title}' : 'ECU تطبیق‌یافته مشخص نیست'),
        ),
      ),
      if (_activeRunningTest != null)
        Card(
          color: const Color(0xFF2A1015),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF2A55))),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'در حال تحریک: ${_activeRunningTest!.name} (${_actuatorRemainingSeconds}s باقی‌مانده)',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF2A55)),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _stopCurrentActuatorTest,
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF2A55), foregroundColor: Colors.white),
                  child: const Text('توقف اضطراری'),
                )
              ],
            ),
          ),
        ),
      const SizedBox(height: 10),
      const Text('عملگرهای قابل تحریک بر روی این خودرو:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
      const SizedBox(height: 6),
      ...verifiedActuatorTests.map((test) {
        final supported = _isActuatorSupportedForCurrentEcu(test);
        final isRunning = _activeRunningTest?.id == test.id;

        return Card(
          color: isRunning ? const Color(0xFF13221A) : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: supported ? const Color(0xFF00F0FF).withOpacity(0.15) : Colors.white10,
              child: Icon(test.icon, color: supported ? const Color(0xFF00F0FF) : Colors.white24),
            ),
            title: Text(test.name, style: TextStyle(color: supported ? Colors.white : Colors.white38, fontWeight: FontWeight.w700)),
            subtitle: Text('${test.group} • ${test.protocol.name.toUpperCase()} • ${supported ? 'سازگار با ECU' : 'عدم پشتیبانی در این مدل'}',
                style: TextStyle(fontSize: 11, color: supported ? const Color(0xFF00E676) : Colors.white24)),
            trailing: isRunning
                ? OutlinedButton(
                    onPressed: _stopCurrentActuatorTest,
                    child: Text('${_actuatorRemainingSeconds}s توقف', style: const TextStyle(color: Color(0xFFFF2A55))),
                  )
                : FilledButton(
                    onPressed: (supported && _connected && !_actuatorActionInProgress) ? () => _runActuatorTest(test) : null,
                    child: const Text('تحریک'),
                  ),
          ),
        );
      }),
      const Divider(height: 32),
      const Text('وضعیت خواندنی عملگرها (Passive Monitoring):', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
      const SizedBox(height: 6),
      ..._availableActuatorDefinitions.map(_actuatorStatusCard),
      if (_actuatorStates.containsKey('وضعیت سیستم سوخت 1'))
        _actuatorStatusCard(const _ActuatorStatusDefinition(name: 'وضعیت سیستم سوخت 1', group: 'OBD-II', icon: Icons.local_gas_station_rounded, source: _ActuatorSourceType.obdPid, idHex: '03')),
    ]);
  }

  Widget _ecuTab() => ListView(padding: const EdgeInsets.all(14), children: [
        Card(child: ListTile(leading: const Icon(Icons.memory, color: Color(0xFF00F0FF), size: 32), title: const Text('مدل ECU'), subtitle: Text(_ecuModel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), trailing: _scanInProgress ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator()) : IconButton(onPressed: _identifyVehicle, icon: const Icon(Icons.refresh)))),
        _info('بانک ECU', 'RASA ECU Database v1.3 • $_databaseStatus'),
        _info('خودرو / خانواده', _matchedEcu?.model ?? _profile.family),
        _info('سازنده / مدل ECU', _matchedEcu == null ? _profile.title : _matchedEcu!.title),
        _info('ECU ID / Part', _hwId),
        _info('ECU Software ID', _swId),
        _info('پروتکل', '$_protocol • Code $_protocolCode'),
        _info('هدر درخواست', _udsRequestHeader.isNotEmpty ? _udsRequestHeader : (_matchedEcu?.requestHeader ?? _profile.header ?? 'Trace / Auto')),
        _info('هدر پاسخ', _udsResponseHeader.isNotEmpty ? _udsResponseHeader : '---'),
        _info('روش شناسایی', _discoveryMethod),
        _info('VIN', _vin),
        _info('Adapter', _adapterInfo),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: _connected ? _identifyVehicle : null, icon: const Icon(Icons.manage_search), label: const Text('شناسایی مجدد ECU')),
        FilledButton.icon(onPressed: _connected && !_databaseScanning ? _discoverEcuDatabase : null, icon: const Icon(Icons.account_tree_rounded), label: const Text('Discovery + تطبیق با بانک ECU')),
        FilledButton.icon(onPressed: _discoveryTrace.isNotEmpty ? _saveDiscoverySnapshot : null, icon: const Icon(Icons.save_alt), label: const Text('ذخیره Trace')),
        const SizedBox(height: 8),
        if (_dbMatches.isNotEmpty) ...[
          Text('نتایج بانک ECU (${_dbMatches.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ..._dbMatches.map((e) => Card(child: ListTile(
            leading: Icon(e.confidence == EcuConfidence.verified ? Icons.verified : Icons.warning_amber_rounded, color: e.confidence == EcuConfidence.verified ? const Color(0xFF00E676) : const Color(0xFFFFD600)),
            title: Text(e.title),
            subtitle: Text('${e.model} • ${e.protocolName}\n${e.sourceNote}'),
            isThreeLine: true,
          ))),
        ],
        if (_discoveryTrace.isNotEmpty) ...[
          const SizedBox(height: 8), const Text('Trace Discovery', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Card(child: Padding(padding: const EdgeInsets.all(10), child: SelectableText(_discoveryTrace.join('\n'), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)))),
        ],
      ]);

  Widget _info(String a, String b) => Card(child: ListTile(title: Text(a, style: const TextStyle(color: Colors.white54, fontSize: 12)), subtitle: SelectableText(b, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))));

  Widget _terminalTab() => Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Expanded(child: Card(child: ListView.builder(reverse: true, itemCount: _logs.length, itemBuilder: (_, i) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(_logs[_logs.length - 1 - i], style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF00F0FF))))))),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: TextField(controller: _terminalController, decoration: const InputDecoration(hintText: '010C / 03 / ATRV / ATDP'))), IconButton(onPressed: () { final c = _terminalController.text; _terminalController.clear(); if (c.isNotEmpty) _sendManual(c); }, icon: const Icon(Icons.send, color: Color(0xFF00F0FF)))]),
      ]));
}

class RasaGauge extends StatelessWidget {
  final String label, value, unit;
  final double progress;
  const RasaGauge({super.key, required this.label, required this.value, required this.unit, required this.progress});
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [Text(label, style: const TextStyle(color: Colors.white54)), const SizedBox(height: 10), SizedBox(width: 120, height: 120, child: Stack(alignment: Alignment.center, children: [CustomPaint(size: const Size(120, 120), painter: GaugePainter(progress: progress)), Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF00F0FF))), Text(unit, style: const TextStyle(fontSize: 10, color: Colors.white54))])]))])));
}

class GaugePainter extends CustomPainter {
  final double progress;
  GaugePainter({required this.progress});
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2), r = size.width / 2 - 8;
    final bg = Paint()..color = Colors.white10..style = PaintingStyle.stroke..strokeWidth = 9..strokeCap = StrokeCap.round;
    final fg = Paint()..color = const Color(0xFF00F0FF)..style = PaintingStyle.stroke..strokeWidth = 9..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), pi * .75, pi * 1.5, false, bg);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), pi * .75, pi * 1.5 * progress.clamp(0.0, 1.0).toDouble(), false, fg);
  }
  @override
  bool shouldRepaint(covariant GaugePainter old) => old.progress != progress;
}
