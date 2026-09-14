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
              // Production licensing must be verified by a server.
              // No master password or reversible key is embedded in the APK.
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


// ---------------------------------------------------------------------------
// PROFESSIONAL DIAGNOSTIC CORE - UDS / ISO-TP / ECU-SPECIFIC DEFINITIONS
// ---------------------------------------------------------------------------

enum DiagnosticProtocol { obd, kwp, udsCan }

class OdometerDefinition {
  final String id, ecuFamily, serviceHex, didHex, unit, verification, sessionHex;
  final DiagnosticProtocol protocol;
  final int dataOffset, dataLength;
  final bool bigEndian;
  final double scale, offset;
  const OdometerDefinition({required this.id, required this.protocol, required this.ecuFamily, required this.serviceHex, required this.didHex, required this.dataLength, required this.verification, this.sessionHex='', this.dataOffset=0, this.bigEndian=true, this.scale=1, this.offset=0, this.unit='KM'});
}

class ActuatorDefinition {
  final String id, label, ecuFamily, sessionHex, serviceHex, identifierHex, startPayloadHex, stopPayloadHex, positivePrefixHex, safety;
  final DiagnosticProtocol protocol;
  final int maxRunMs;
  const ActuatorDefinition({required this.id, required this.label, required this.protocol, required this.ecuFamily, required this.serviceHex, required this.identifierHex, required this.startPayloadHex, required this.stopPayloadHex, required this.positivePrefixHex, required this.safety, this.sessionHex='', this.maxRunMs=1500});
}

// OEM-specific DIDs/RIDs are deliberately empty until verified for the exact ECU.
// RASA never guesses an odometer DID or an actuator command.
const List<OdometerDefinition> verifiedOdometerDefinitions = <OdometerDefinition>[];
const List<ActuatorDefinition> verifiedActuatorDefinitions = <ActuatorDefinition>[
  ActuatorDefinition(
    id:'ME744_FAN_LOW', label:'فن دور کند', protocol:DiagnosticProtocol.kwp,
    ecuFamily:'ME7.4.x', serviceHex:'', identifierHex:'',
    startPayloadHex:'', stopPayloadHex:'', positivePrefixHex:'',
    safety:'سوئیچ روشن، موتور خاموش، خودرو ثابت و ECU در وضعیت مجاز/Unlocked.',
    maxRunMs:20000,
  ),
  ActuatorDefinition(
    id:'ME744_FAN_HIGH', label:'فن دور تند', protocol:DiagnosticProtocol.kwp,
    ecuFamily:'ME7.4.x', serviceHex:'', identifierHex:'',
    startPayloadHex:'', stopPayloadHex:'', positivePrefixHex:'',
    safety:'سوئیچ روشن، موتور خاموش، خودرو ثابت و ECU در وضعیت مجاز/Unlocked.',
    maxRunMs:25000,
  ),
  ActuatorDefinition(
    id:'ME744_FUEL_RELAY', label:'پمپ بنزین / رله دوبل', protocol:DiagnosticProtocol.kwp,
    ecuFamily:'ME7.4.x', serviceHex:'', identifierHex:'',
    startPayloadHex:'', stopPayloadHex:'', positivePrefixHex:'',
    safety:'سوئیچ روشن، موتور خاموش، خودرو ثابت و ECU در وضعیت مجاز/Unlocked.',
    maxRunMs:10000,
  ),
  ActuatorDefinition(
    id:'ME744_CANISTER', label:'شیر برقی کنیستر', protocol:DiagnosticProtocol.kwp,
    ecuFamily:'ME7.4.x', serviceHex:'', identifierHex:'',
    startPayloadHex:'', stopPayloadHex:'', positivePrefixHex:'',
    safety:'سوئیچ روشن، موتور خاموش، خودرو ثابت و ECU در وضعیت مجاز/Unlocked.',
    maxRunMs:10000,
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

  // Single Frame
  if(pci==0){
    final len=first[0]&0x0F;
    if(first.length<1+len) return null;
    return IsoTpMessage(first.sublist(1,1+len));
  }

  // First Frame + Consecutive Frames
  if(pci==1 && first.length>=2){
    final total=((first[0]&0x0F)<<8)|first[1];
    final payload=<int>[];
    payload.addAll(first.sublist(2));
    int sn=1;

    for(final f in frames.skip(1)){
      if(f.isEmpty) continue;

      // ELM may expose the tester's Flow Control frame in the stream.
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

  // Some adapters/ELM configurations already remove ISO-TP PCI.
  if(first[0]>=0x40 && first[0]<=0x7F) {
    return IsoTpMessage(first);
  }

  return null;
}

class DiagnosticFrame {
  final String command;
  final String response;
  final DateTime time;
  DiagnosticFrame(this.command, this.response) : time = DateTime.now();
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

  EcuProfile _profile = ecuProfiles.last;
  String _protocol = 'Unknown';
  String _ecuModel = 'شناسایی نشده';
  String _ecuSoftware = '---';
  String _vin = '---';
  String _adapterInfo = '---';
  String _connectionStatus = 'آماده اتصال';

  int _rpm = 0, _speed = 0, _coolant = 0, _throttle = 0, _engineLoad = 0, _iat = 0;
  double _voltage = 0, _o2 = 0, _odometer = 0;
  String _odometerStatus = 'استعلام نشده';
  String _activeActuator = '';
  bool _loadingDtc = false;
  bool _clearingDtc = false;
  int _pollIndex = 0;

  final _terminalController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 7, vsync: this);
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
    // Old Android releases may use location for discovery.
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
    await _sendAndWait('ATAT1', timeout: const Duration(seconds: 1), logCommand: true);
    await _sendAndWait('ATSP0', timeout: const Duration(seconds: 2), logCommand: true);
    final dp = await _sendAndWait('ATDP', timeout: const Duration(seconds: 1), logCommand: true);
    _protocol = _firstUsefulLine(dp, 'Auto');
    _log('PROTOCOL $_protocol');
  }

  Future<void> _applyProfile(EcuProfile p) async {
    if (!_connected) return;
    _pollTimer?.cancel();
    setState(() {
      _profile = p;
      _supportsOdometer = false;
      _odometer = 0;
      _odometerStatus = 'استعلام نشده';
    });
    await _sendAndWait(p.protocol == 'OBD-II' ? 'ATSP0' : p.protocol.contains('KWP') ? 'ATSP5' : 'ATSP6', timeout: const Duration(seconds: 2));
    if (p.header != null) await _sendAndWait(p.header!, timeout: const Duration(seconds: 1));
    _startPolling();
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

      // Generic OBD identification. These are optional; NO DATA is valid.
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
      _connectionStatus = 'ECU پاسخ‌گو';
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

    // UDS positive responses.
    if(pdu.isNotEmpty){
      final service=pdu[0];
      final positiveToOriginal=<int,int>{
        0x50:0x10, // DiagnosticSessionControl
        0x54:0x14, // ClearDiagnosticInformation
        0x59:0x19, // ReadDTCInformation
        0x62:0x22, // ReadDataByIdentifier
        0x6F:0x2F, // InputOutputControlByIdentifier
        0x71:0x31, // RoutineControl
        0x7E:0x3E, // TesterPresent
      };
      final original=positiveToOriginal[service];
      if(original!=null) key=_findUdsWaiterByService(original);

      // UDS NegativeResponse: 7F <service> <NRC>
      if(service==0x7F && pdu.length>=2){
        key=_findUdsWaiterByService(pdu[1]);
      }
    }

    // Standard OBD responses.
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

    // AT commands and adapters that return an unframed UDS response.
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
    final o2 = _parsePid(response, '14');
    if (mounted) {
      setState(() {
        if (speed != null) _speed = speed;
        if (coolant != null) _coolant = coolant - 40;
        if (throttle != null) _throttle = ((throttle * 100) / 255).round();
        if (load != null) _engineLoad = ((load * 100) / 255).round();
        if (iat != null) _iat = iat - 40;
        if (o2 != null) _o2 = o2 / 200.0;
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
      _snack('ابتدا اتصال ECU را برقرار کنید.');
      return;
    }
    _pollTimer?.cancel();
    setState(() { _loadingDtc = true; _dtcs.clear(); });
    final r = await _sendAndWait('03', timeout: const Duration(seconds: 4), logCommand: true);
    if (r.isEmpty && mounted) setState(() => _loadingDtc = false);
    _startPolling();
  }

  Future<void> _clearDtc() async {
    if (!_connected) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأیید پاک‌سازی خطا'),
        content: const Text('پاک کردن DTC ممکن است مانیتورهای OBD را Reset کند. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('پاک کن')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _clearingDtc = true);
    final r = await _sendAndWait('04', timeout: const Duration(seconds: 4), logCommand: true);
    setState(() {
      _clearingDtc = false;
      if (r.isNotEmpty && !r.toUpperCase().contains('ERROR')) _dtcs.clear();
    });
    _startPolling();
  }

  OdometerDefinition? _findOdometerDefinition() {
    final family=_profile.family.toUpperCase(), model=_profile.model.toUpperCase();
    for(final d in verifiedOdometerDefinitions){ if(family.contains(d.ecuFamily.toUpperCase())||model.contains(d.ecuFamily.toUpperCase())) return d; }
    return null;
  }

  Future<void> _readOdometer() async {
    if (!_connected) return;
    _pollTimer?.cancel();
    setState(()=>_odometerStatus='در حال تطبیق ECU...');
    final def=_findOdometerDefinition();
    if(def==null){
      setState(() { _supportsOdometer=false; _odometer=0; _odometerStatus='برای این ECU هنوز DID کارکرد تأیید نشده است'; });
      _log('ODOMETER: NO VERIFIED ECU-SPECIFIC DEFINITION'); _startPolling(); return;
    }
    try{
      if(def.protocol!=DiagnosticProtocol.udsCan) throw Exception('KWP odometer transport requires a verified ECU definition');
      await _sendAndWait('ATCAF1'); await _sendAndWait('ATCFC1'); if(_profile.header!=null) await _sendAndWait(_profile.header!);
      if(def.sessionHex.isNotEmpty){ final sr=await _udsRequest(def.sessionHex); if(!_udsPositive(sr,def.sessionHex)) throw Exception('session rejected'); }
      final r=await _udsRequest(def.serviceHex+def.didHex);
      final payload=_isoTpReassemble(r)?.payload ?? _hexBytes(r);
      final value=_decodeDefinitionValue(payload,def); if(value==null) throw Exception('invalid response');
      setState(() { _supportsOdometer=true; _odometer=value; _odometerStatus='${value.toStringAsFixed(0)} ${def.unit}'; });
      _log('ODOMETER OK ${def.id}: ${value.toStringAsFixed(0)} ${def.unit}');
    }catch(e){ setState(() { _supportsOdometer=false; _odometerStatus='استعلام ناموفق: ${e.toString().replaceFirst('Exception: ','')}'; }); _log('ODOMETER ERROR $e'); }
    finally{ _startPolling(); }
  }

  double? _decodeDefinitionValue(List<int> payload,OdometerDefinition def){
    if(def.dataLength<=0||def.dataOffset<0||payload.length<def.dataOffset+def.dataLength) return null;
    final data=payload.sublist(def.dataOffset,def.dataOffset+def.dataLength); int value=0;
    if(def.bigEndian){for(final b in data)value=(value<<8)|b;}else{for(int i=data.length-1;i>=0;i--)value=(value<<8)|data[i];}
    return value*def.scale+def.offset;
  }

  Future<String> _udsRequest(String payloadHex) async {
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

    _log('UDS TX $request');

    try{
      // ELM327/STN devices perform ISO-TP framing when CAN protocol is selected.
      _connection!.output.add(Uint8List.fromList(utf8.encode('$request\r')));
      await _connection!.output.allSent;

      final response=await c.future.timeout(
        const Duration(seconds:4),
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

    // Positive response SID = request SID + 0x40.
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

  Future<void> _runUdsIdentification() async {
    if(!_connected){
      _snack('ابتدا ECU را متصل کنید.');
      return;
    }

    if(!(_profile.protocol.contains('UDS')||_profile.protocol.contains('CAN'))){
      _snack('پروفایل فعلی CAN/UDS نیست.');
      return;
    }

    _pollTimer?.cancel();

    try{
      await _sendAndWait('ATSP6',timeout:const Duration(seconds:2),logCommand:true);
      await _sendAndWait('ATH1',timeout:const Duration(seconds:1),logCommand:true);
      await _sendAndWait('ATCAF1',timeout:const Duration(seconds:1),logCommand:true);
      await _sendAndWait('ATCFC1',timeout:const Duration(seconds:1),logCommand:true);
      await _sendAndWait(_profile.header??'ATSH 7E0',timeout:const Duration(seconds:1),logCommand:true);

      final response=await _udsReadDid(0xF190);
      final vin=_decodeUdsVin(response);

      if(vin.isNotEmpty){
        setState(()=>_vin=vin);
        _log('UDS VIN OK $vin');
      }else{
        _log('UDS VIN DID F190 not supported or no valid response');
      }
    }finally{
      _startPolling();
    }
  }

  bool _isExecutableActuator(ActuatorDefinition d) =>
      d.serviceHex.isNotEmpty &&
      d.identifierHex.isNotEmpty &&
      d.startPayloadHex.isNotEmpty &&
      d.stopPayloadHex.isNotEmpty &&
      d.positivePrefixHex.isNotEmpty;

  ActuatorDefinition? _findActuatorDefinition(String name){
    final f=_profile.family.toUpperCase(), m=_profile.model.toUpperCase();
    for(final a in verifiedActuatorDefinitions){ if(a.label==name&&(f.contains(a.ecuFamily.toUpperCase())||m.contains(a.ecuFamily.toUpperCase()))) return a; }
    return null;
  }

  Future<void> _runActuator(String name) async {
    if(!_connected){_snack('ابتدا ECU را متصل کنید.');return;}
    final def=_findActuatorDefinition(name);
    if(def==null){
      await showDialog(context:context,builder:(_)=>AlertDialog(title:Text('$name — قفل ایمنی'),content:const Text('برای ECU فعلی فرمان تأییدشده این عملگر در بانک RASA وجود ندارد.\n\nRASA هیچ فرمان حدسی 2F/30/31 یا RID ناشناخته ارسال نمی‌کند.'),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('متوجه شدم'))]));
      return;
    }
    if(!_isExecutableActuator(def)){
      await showDialog(
        context:context,
        builder:(_)=>AlertDialog(
          title:Text('$name — قفل ایمنی'),
          content:Text(
            'قابلیت این عملگر برای خانواده ${def.ecuFamily} مستند شده است، '
            'اما فرمان بایتی دقیق همین ECU هنوز تأیید نشده است.\\n\\n'
            'بنابراین RASA فقط قابلیت را نمایش می‌دهد و هیچ فرمان حدسی ارسال نمی‌کند.'
          ),
          actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('متوجه شدم'))],
        ),
      );
      return;
    }
    final ok=await showDialog<bool>(context:context,builder:(_)=>AlertDialog(title:Text('تست $name'),content:Text('${def.safety}\n\nحداکثر زمان اجرا ${def.maxRunMs}ms. ادامه؟'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('انصراف')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('شروع تست'))]));
    if(ok!=true)return;
    _pollTimer?.cancel(); setState(()=>_activeActuator=name);
    try{
      if(def.sessionHex.isNotEmpty){final sr=await _sendAndWait(def.sessionHex,timeout:const Duration(seconds:3),logCommand:true);if(!_udsPositive(sr,def.sessionHex))throw Exception('Diagnostic Session تأیید نشد');}
      final start=def.serviceHex+def.identifierHex+def.startPayloadHex, stop=def.serviceHex+def.identifierHex+def.stopPayloadHex;
      final sr=await _sendAndWait(start,timeout:const Duration(seconds:3),logCommand:true);if(!_udsPositive(sr,def.serviceHex))throw Exception('پاسخ مثبت شروع دریافت نشد');
      await Future.delayed(Duration(milliseconds:def.maxRunMs));
      final tr=await _sendAndWait(stop,timeout:const Duration(seconds:3),logCommand:true);if(!_udsPositive(tr,def.serviceHex))_log('ACTUATOR STOP NOT CONFIRMED');else _snack('$name با پاسخ مثبت اجرا و متوقف شد.');
    }catch(e){_log('ACTUATOR ERROR $e');_snack('تست اجرا نشد: $e');}finally{setState(()=>_activeActuator='');_startPolling();}
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (!_connected || _activeActuator.isNotEmpty) return;
    _pollIndex = 0;
    const commands = ['010C', '010D', '0105', '0111', '0104', '010F', '0114', 'ATRV'];
    _pollTimer = Timer.periodic(const Duration(milliseconds: 450), (_) async {
      if (!_connected || _requestInFlight || _activeActuator.isNotEmpty) return;
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
        _voltage = 13.8 + r.nextDouble() * .3;
        _o2 = .35 + r.nextDouble() * .45;
        _ecuModel = 'DEMO ECU';
        _protocol = 'DEMO';
      });
    });
  }

  Future<void> _disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _serialSub?.cancel();
    _serialSub = null;
    try { await _connection?.finish(); } catch (_) {}
    try { _connection?.dispose(); } catch (_) {}
    _connection = null;
    if (mounted) setState(() { _connected = false; _connecting = false; _activeActuator = ''; _connectionStatus = 'آماده اتصال'; });
  }

  void _snack(String s) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RASA DIAG PRO', style: TextStyle(fontWeight: FontWeight.w900)),
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
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _dashboard(), _vehicleTab(), _sensorsTab(), _dtcTab(), _actuatorTab(), _ecuTab(), _terminalTab(),
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
        const SizedBox(height: 12),
        _ecuMiniCard(),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.add_road_rounded, color: Color(0xFF00F0FF)),
          title: const Text('کارکرد خودرو'),
          subtitle: Text(_odometerStatus),
          trailing: FilledButton(onPressed: _connected ? _readOdometer : null, child: const Text('استعلام')),
        )),
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
        const Text('انتخاب خانواده ECU', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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

  Widget _actuatorTab(){
    final items=['فن دور کند','فن دور تند','پمپ بنزین / رله دوبل','شیر برقی کنیستر','چراغ MIL'];
    final executableCount = verifiedActuatorDefinitions.where(_isExecutableActuator).length;
    return ListView(padding:const EdgeInsets.all(14),children:[
      Card(child:ListTile(leading:Icon(executableCount > 0 ? Icons.verified : Icons.lock_outline,color:executableCount > 0 ? const Color(0xFF00E676) : const Color(0xFFFFD600)),title:Text(executableCount > 0 ? 'بانک عملگر آماده است' : 'بانک عملگر ECU هنوز تأیید نشده'),subtitle:Text('ECU: ${_profile.title}'))),
      const SizedBox(height:8),
      Card(color:const Color(0xFF17120F),child:const Padding(padding:EdgeInsets.all(14),child:Row(children:[Icon(Icons.warning_amber_rounded,color:Color(0xFFFFD600)),SizedBox(width:10),Expanded(child:Text('فرمان حدسی ارسال نمی‌شود. هر عملگر باید سرویس، شناسه، payload شروع/توقف، پاسخ مثبت و شرط ایمنی تأییدشده داشته باشد.',style:TextStyle(color:Colors.white70)))]))),
      const SizedBox(height:10),
      ...items.map((name){final def=_findActuatorDefinition(name); final enabled=def!=null&&_isExecutableActuator(def)&&_connected&&_activeActuator.isEmpty;return Card(child:ListTile(leading:Icon(enabled?Icons.build_circle:Icons.lock_outline,color:enabled?const Color(0xFF00F0FF):Colors.white30),title:Text(name),subtitle:Text(enabled?'فرمان تأییدشده':'برای ECU فعلی فعال نیست'),trailing:FilledButton(onPressed:enabled?()=>_runActuator(name):null,child:Text(_activeActuator==name?'در حال اجرا':'تست'))));}),
    ]);
  }

  Widget _ecuTab() => ListView(padding: const EdgeInsets.all(14), children: [
        Card(child: ListTile(leading: const Icon(Icons.memory, color: Color(0xFF00F0FF), size: 32), title: const Text('مدل ECU'), subtitle: Text(_ecuModel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), trailing: _scanInProgress ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator()) : IconButton(onPressed: _identifyVehicle, icon: const Icon(Icons.refresh)))),
        _info('خودرو / خانواده', _profile.family),
        _info('پروتکل', _protocol),
        _info('هدر CAN / KWP', _profile.header ?? 'Auto / Functional'),
        _info('VIN', _vin),
        _info('ECU Software', _ecuSoftware),
        _info('Adapter', _adapterInfo),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: _connected ? _identifyVehicle : null, icon: const Icon(Icons.manage_search), label: const Text('شناسایی مجدد ECU')),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _connected && (_profile.protocol.contains('UDS') || _profile.protocol.contains('CAN'))
              ? _runUdsIdentification
              : null,
          icon: const Icon(Icons.alt_route_rounded),
          label: const Text('خواندن VIN از UDS'),
        ),
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
