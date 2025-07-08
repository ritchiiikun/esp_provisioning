import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:esp_provisioning_example/ble_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'ble.dart';

class BleBloc extends Bloc<BleEvent, BleState> {
  var bleService = BleService.getInstance();
  StreamSubscription<ScanResult>? _scanSubscription;
  List<Map<String, dynamic>> bleDevices = [];

  BleBloc(BleState initialState) : super(initialState);

  @override
  Stream<BleState> mapEventToState(BleEvent event) async* {
    if (event is BleEventStart) {
      yield* _mapStartToState();
    } else if (event is BleEventDeviceUpdated) {
      yield BleStateLoaded(List.from(event.bleDevices));
    } else if (event is BleEventSelect) {
      bleService.select(event.selectedDevice['device']);
    } else if (event is BleEventStopScan) {
      await bleService.stopScanBle();
    }
  }

  Stream<BleState> _mapStartToState() async* {
    var permissionIsGranted = await bleService.requestBlePermissions();
    if (!permissionIsGranted) {
      add(BleEventPermissionDenied());
      return;
    }
    var bleState = await bleService.start();
    // BluetoothAdapterState.unauthorized is the new unauthorized state
    if (bleState == BluetoothAdapterState.unauthorized) {
      add(BleEventPermissionDenied());
      return;
    }
    await _scanSubscription?.cancel();
    _scanSubscription = bleService
        .scanBle()
        .debounce((_) => TimerStream(true, Duration(milliseconds: 100)))
        .listen((ScanResult scanResult) {
          var bleDevice = BleDevice(scanResult);
          if (bleDevice.name != "Unknown") {
            var idx = bleDevices.indexWhere((e) => e['id'] == bleDevice.id);

            if (idx < 0) {
              bleDevices.add(bleDevice.toMap());
            } else {
              bleDevices[idx] = bleDevice.toMap();
            }
            add(BleEventDeviceUpdated(bleDevices));
          }
        });
  }

  @override
  Future<void> close() async {
    await _scanSubscription?.cancel();
    await bleService.stopScanBle();
    return super.close();
  }
}
