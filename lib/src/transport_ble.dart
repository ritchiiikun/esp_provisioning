import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'transport.dart';

class TransportBLE implements ProvTransport {
  final BluetoothDevice device;
  final String serviceUUID;
  final Map<String, String> lockupTable;
  late final Map<String, String> nuLookup;

  static const PROV_BLE_SERVICE = '021a9004-0382-4aea-bff4-6b3f1c5adfb4';
  static const PROV_BLE_EP = {
    'prov-scan': 'ff50',
    'prov-session': 'ff51',
    'prov-config': 'ff52',
    'proto-ver': 'ff53',
    'custom-data': 'ff54',
  };

  TransportBLE(
    this.device, {
    this.serviceUUID = PROV_BLE_SERVICE,
    this.lockupTable = PROV_BLE_EP,
  }) {
    nuLookup = <String, String>{};
    for (var name in lockupTable.keys) {
      var charsInt = int.parse(lockupTable[name]!, radix: 16);
      var serviceHex = charsInt.toRadixString(16).padLeft(4, '0');
      nuLookup[name] =
          serviceUUID.substring(0, 4) + serviceHex + serviceUUID.substring(8);
    }
  }

  Future<bool> connect() async {
    var state = await device.state.first;
    if (state == BluetoothDeviceState.connected) {
      return true;
    }
    await device.connect(autoConnect: false);
    // Wait for connection
    await device.state.firstWhere((s) => s == BluetoothDeviceState.connected);
    return true;
  }

  Future<Uint8List> sendReceive(String epName, Uint8List data) async {
    final services = await device.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid.toString().toLowerCase() == serviceUUID.toLowerCase(),
      orElse: () => throw Exception('Service $serviceUUID not found'),
    );
    final charUuid = nuLookup[epName]!.toLowerCase();
    final characteristic = service.characteristics.firstWhere(
      (c) => c.uuid.toString().toLowerCase().endsWith(charUuid),
      orElse: () => throw Exception('Characteristic $charUuid not found'),
    );
    if (data.isNotEmpty) {
      await characteristic.write(data, withoutResponse: false);
    }
    final value = await characteristic.read();
    return Uint8List.fromList(value);
  }

  Future<void> disconnect() async {
    var state = await device.state.first;
    if (state == BluetoothDeviceState.connected) {
      await device.disconnect();
    }
  }

  Future<bool> checkConnect() async {
    var state = await device.state.first;
    return state == BluetoothDeviceState.connected;
  }

  void dispose() {
    // No-op for now
  }
}
