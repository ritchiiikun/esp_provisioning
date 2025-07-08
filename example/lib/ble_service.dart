import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esp_provisioning/esp_provisioning.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:location/location.dart' as location;

class BleService {
  static final BleService _instance = BleService._internal();
  static final Logger log = Logger(printer: PrettyPrinter());
  bool _isPowerOn = false;
  StreamSubscription<BluetoothAdapterState>? _stateSubscription;
  BluetoothDevice? selectedDevice;
  List<String>? serviceUUIDs;

  factory BleService.getInstance() => _instance;
  BleService._internal();

  Future<BluetoothAdapterState> start() async {
    log.i('Ble service start');
    if (_isPowerOn) {
      var state = await _waitForBluetoothPoweredOn();
      log.i('Device power was on $state');
      return state;
    }
    var isPermissionOk = await requestBlePermissions();
    if (!isPermissionOk) {
      throw Exception('Location permission not granted');
    }
    try {
      BluetoothAdapterState state = await _waitForBluetoothPoweredOn();
      _isPowerOn = state == BluetoothAdapterState.on;
      return state;
    } catch (e) {
      log.e('Error ${e.toString()}');
    }
    return BluetoothAdapterState.unknown;
  }

  void select(BluetoothDevice device) async {
    if (selectedDevice != null) {
      await selectedDevice!.disconnect();
    }
    selectedDevice = device;
    log.v('selectedDevice = $selectedDevice');
  }

  Future<bool> stop() async {
    if (!_isPowerOn) {
      return true;
    }
    _isPowerOn = false;
    await stopScanBle();
    await _stateSubscription?.cancel();
    if (selectedDevice != null) {
      await selectedDevice!.disconnect();
    }
    return true;
  }

  Stream<ScanResult> scanBle() {
    stopScanBle();
    return FlutterBluePlus.instance.scan(
      withServices: [Guid(TransportBLE.PROV_BLE_SERVICE)],
      scanMode: ScanMode.balanced,
      allowDuplicates: true,
    );
  }

  Future<void> stopScanBle() async {
    await FlutterBluePlus.instance.stopScan();
  }

  Future<EspProv> startProvisioning({
    BluetoothDevice? device,
    String pop = 'abcd1234',
  }) async {
    if (!_isPowerOn) {
      await _waitForBluetoothPoweredOn();
    }
    BluetoothDevice d = device ?? selectedDevice!;
    log.v('device $d');
    await FlutterBluePlus.instance.stopScan();
    EspProv prov = EspProv(
      transport: TransportBLE(d),
      security: Security1(pop: pop),
    );
    await prov.establishSession();
    return prov;
  }

  Future<BluetoothAdapterState> _waitForBluetoothPoweredOn() async {
    Completer<BluetoothAdapterState> completer =
        Completer<BluetoothAdapterState>();
    _stateSubscription?.cancel();
    _stateSubscription = FlutterBluePlus.instance.adapterState.listen((state) {
      log.v('bluetoothState = $state');
      if ((state == BluetoothAdapterState.on ||
              state == BluetoothAdapterState.unauthorized) &&
          !completer.isCompleted) {
        completer.complete(state);
      }
    });
    return completer.future.timeout(
      Duration(seconds: 5),
      onTimeout: () => BluetoothAdapterState.unknown,
    );
  }

  Future<bool> requestBlePermissions() async {
    location.Location _location = location.Location();
    bool _serviceEnabled;

    _serviceEnabled = await _location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await _location.requestService();
      if (!_serviceEnabled) {
        return false;
      }
    }
    var isLocationGranted = await Permission.locationWhenInUse.request();
    log.v('checkBlePermissions, isLocationGranted=$isLocationGranted');
    return isLocationGranted == PermissionStatus.granted;
  }
}
