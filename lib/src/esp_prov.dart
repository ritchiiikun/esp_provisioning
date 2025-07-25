import 'dart:convert';
import 'dart:typed_data';

import 'package:esp_provisioning/src/connection_models.dart';

import 'proto/dart/constants.pbenum.dart';
import 'proto/dart/session.pb.dart';
import 'proto/dart/wifi_config.pb.dart';
import 'proto/dart/wifi_scan.pb.dart';
import 'security.dart';
import 'transport.dart';

class EspProv {
  final ProvTransport transport;
  final ProvSecurity security;

  EspProv({required this.transport, required this.security});

  Future<void> establishSession() async {
    SessionData? responseData;

    await transport.disconnect();

    if (await transport.connect()) {
      while (await transport.checkConnect()) {
        var request = await security.securitySession(responseData);
        var response = await transport.sendReceive(
          'prov-session',
          request.writeToBuffer(),
        );
        if (response.isEmpty) {
          throw Exception('Empty response');
        }
        responseData = SessionData.fromBuffer(response);
      }
    }
    return;
  }

  Future<void> dispose() async {
    return await transport.disconnect();
  }

  Future<List<WifiAP>> startScanWiFi() async {
    return await scan();
  }

  Future<WiFiScanPayload> startScanResponse(Uint8List data) async {
    var respPayload = WiFiScanPayload.fromBuffer(await security.decrypt(data));
    if (respPayload.msg != WiFiScanMsgType.TypeRespScanStart) {
      throw Exception('Invalid expected message type $respPayload');
    }
    return respPayload;
  }

  Future<WiFiScanPayload> startScanRequest({
    bool blocking = true,
    bool passive = false,
    int groupChannels = 5,
    int periodMs = 0,
  }) async {
    WiFiScanPayload payload = WiFiScanPayload();
    payload.msg = WiFiScanMsgType.TypeCmdScanStart;
    payload.cmdScanStart = CmdScanStart()
      ..blocking = blocking
      ..passive = passive
      ..groupChannels = groupChannels
      ..periodMs = periodMs;
    var response = await transport.sendReceive(
      'prov-scan',
      payload.writeToBuffer(),
    );
    return WiFiScanPayload.fromBuffer(await security.decrypt(response));
  }

  Future<WiFiScanPayload> scanStatusRequest() async {
    WiFiScanPayload payload = WiFiScanPayload();
    payload.msg = WiFiScanMsgType.TypeCmdScanStatus;
    payload.cmdScanStatus = CmdScanStatus();
    var response = await transport.sendReceive(
      'prov-scan',
      payload.writeToBuffer(),
    );
    return WiFiScanPayload.fromBuffer(await security.decrypt(response));
  }

  Future<List<WifiAP>> scanResultResponse(Uint8List data) async {
    var respPayload = WiFiScanPayload.fromBuffer(await security.decrypt(data));
    if (respPayload.msg != WiFiScanMsgType.TypeRespScanResult) {
      throw Exception('Invalid expected message type $respPayload');
    }
    List<WifiAP> ret = [];
    for (var entry in respPayload.respScanResult.entries) {
      ret.add(
        WifiAP(
          ssid: utf8.decode(entry.ssid),
          rssi: entry.rssi,
          private: entry.auth.toString() != 'Open',
        ),
      );
    }
    return ret;
  }

  Future<List<WifiAP>> scan({
    bool blocking = true,
    bool passive = false,
    int groupChannels = 5,
    int periodMs = 0,
  }) async {
    await startScanRequest(
      blocking: blocking,
      passive: passive,
      groupChannels: groupChannels,
      periodMs: periodMs,
    );
    var status = await scanStatusRequest();
    var resultCount = status.respScanStatus.resultCount;
    List<WifiAP> ret = [];
    if (resultCount > 0) {
      var index = 0;
      var remaining = resultCount;
      while (remaining > 0) {
        var count = remaining > 4 ? 4 : remaining;
        var data = await scanResultRequest(startIndex: index, count: count);
        ret.addAll(data);
        remaining -= count;
        index += count;
      }
    }
    return ret;
  }

  Future<WiFiScanPayload> scanResultRequest({
    required int startIndex,
    required int count,
  }) async {
    WiFiScanPayload payload = WiFiScanPayload();
    payload.msg = WiFiScanMsgType.TypeCmdScanResult;
    payload.cmdScanResult = CmdScanResult()
      ..startIndex = startIndex
      ..count = count;
    var response = await transport.sendReceive(
      'prov-scan',
      payload.writeToBuffer(),
    );
    return WiFiScanPayload.fromBuffer(await security.decrypt(response));
  }

  Future<bool> sendWifiConfig({
    required String ssid,
    required String password,
  }) async {
    var payload = WiFiConfigPayload();
    payload.msg = WiFiConfigMsgType.TypeCmdSetConfig;
    payload.cmdSetConfig = CmdSetConfig()
      ..ssid = utf8.encode(ssid)
      ..passphrase = utf8.encode(password);
    var response = await transport.sendReceive(
      'prov-config',
      payload.writeToBuffer(),
    );
    var respPayload = WiFiConfigPayload.fromBuffer(
      await security.decrypt(response),
    );
    return respPayload.status == Status.Success;
  }

  Future<bool> applyWifiConfig() async {
    var payload = WiFiConfigPayload();
    payload.msg = WiFiConfigMsgType.TypeCmdApplyConfig;
    payload.cmdApplyConfig = CmdApplyConfig();
    var response = await transport.sendReceive(
      'prov-config',
      payload.writeToBuffer(),
    );
    var respPayload = WiFiConfigPayload.fromBuffer(
      await security.decrypt(response),
    );
    return respPayload.status == Status.Success;
  }

  Future<ConnectionStatus> getStatus() async {
    var payload = WiFiConfigPayload();
    payload.msg = WiFiConfigMsgType.TypeCmdGetStatus;

    var cmdGetStatus = CmdGetStatus();
    payload.cmdGetStatus = cmdGetStatus;

    var reqData = await security.encrypt(payload.writeToBuffer());
    var respData = await transport.sendReceive('prov-config', reqData);
    var respRaw = await security.decrypt(respData);
    var respPayload = WiFiConfigPayload.fromBuffer(respRaw);

    if (respPayload.respGetStatus.staState.value == 0) {
      return ConnectionStatus(
        state: WifiConnectionState.Connected,
        ip: respPayload.respGetStatus.connected.ip4Addr,
      );
    } else if (respPayload.respGetStatus.staState.value == 1) {
      return ConnectionStatus(state: WifiConnectionState.Connecting);
    } else if (respPayload.respGetStatus.staState.value == 2) {
      return ConnectionStatus(state: WifiConnectionState.Disconnected);
    } else if (respPayload.respGetStatus.staState.value == 3) {
      if (respPayload.respGetStatus.failReason.value == 0) {
        return ConnectionStatus(
          state: WifiConnectionState.ConnectionFailed,
          failedReason: WifiConnectFailedReason.AuthError,
        );
      } else if (respPayload.respGetStatus.failReason.value == 1) {
        return ConnectionStatus(
          state: WifiConnectionState.ConnectionFailed,
          failedReason: WifiConnectFailedReason.NetworkNotFound,
        );
      }
      return ConnectionStatus(state: WifiConnectionState.ConnectionFailed);
    }

    return null;
  }

  Future<Uint8List> sendReceiveCustomData(
    Uint8List data, {
    int packageSize = 256,
  }) async {
    var i = data.length;
    var offset = 0;
    List<int> ret = new List<int>(0);
    while (i > 0) {
      var needToSend = data.sublist(offset, i < packageSize ? i : packageSize);
      var encrypted = await security.encrypt(needToSend);
      var newData = await transport.sendReceive('custom-data', encrypted);

      if (newData.length > 0) {
        var decrypted = await security.decrypt(newData);
        ret += List.from(decrypted);
      }
      i -= packageSize;
    }
    return Uint8List.fromList(ret);
  }
}
