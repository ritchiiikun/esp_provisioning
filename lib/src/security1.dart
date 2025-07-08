import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:cryptography/cryptography.dart';

import 'proto/dart/sec1.pb.dart';
import 'proto/dart/session.pb.dart';
import 'security.dart';
import 'crypt.dart';

class Security1 implements ProvSecurity {
  final String pop;
  final bool verbose;
  SecurityState sessionState;
  SimpleKeyPair? clientKey;
  SimplePublicKey? devicePublicKey;
  Uint8List? deviceRandom;
  Crypt crypt = Crypt();
  X25519 x25519 = X25519();
  Sha256 sha256 = Sha256();

  Security1({
    required this.pop,
    this.sessionState = SecurityState.REQUEST1,
    this.verbose = false,
  });

  void _verbose(dynamic data) {
    if (verbose) {
      print('+++ $data +++');
    }
  }

  Future<Uint8List> encrypt(Uint8List data) async {
    _verbose('raw before process  [38;5;208m${data.toString()} [0m');
    return crypt.crypt(data);
  }

  Future<Uint8List> decrypt(Uint8List data) async {
    return encrypt(data);
  }

  Future<void> _generateKey() async {
    clientKey = await x25519.newKeyPair();
  }

  Uint8List _xor(Uint8List a, Uint8List b) {
    Uint8List ret = Uint8List(max(a.length, b.length));
    for (var i = 0; i < max(a.length, b.length); i++) {
      final _a = i < a.length ? a[i] : 0;
      final _b = i < b.length ? b[i] : 0;
      ret[i] = (_a ^ _b);
    }
    return ret;
  }

  Future<SessionData?> securitySession(SessionData? responseData) async {
    if (sessionState == SecurityState.REQUEST1) {
      sessionState = SecurityState.RESPONSE1_REQUEST2;
      return await setup0Request();
    }
    if (sessionState == SecurityState.RESPONSE1_REQUEST2) {
      sessionState = SecurityState.RESPONSE2;
      await setup0Response(responseData!);
      return await setup1Request(responseData);
    }
    if (sessionState == SecurityState.RESPONSE2) {
      sessionState = SecurityState.FINISH;
      await setup1Response(responseData!);
      return null;
    }
    throw Exception('Unexpected state');
  }

  Future<SessionData> setup0Request() async {
    _verbose('setup0Request');
    var setupRequest = SessionData();

    setupRequest.secVer = SecSchemeVersion.SecScheme1;
    await _generateKey();
    SessionCmd0 sc0 = SessionCmd0();
    List<int> temp = await clientKey!.extractPublicKey().then(
      (value) => value.bytes,
    );
    sc0.clientPubkey = temp;
    Sec1Payload sec1 = Sec1Payload();
    sec1.sc0 = sc0;
    setupRequest.sec1 = sec1;
    _verbose('setup0Request: clientPubkey = ${temp.toString()}');
    return setupRequest;
  }

  Future<SessionData> setup0Response(SessionData responseData) async {
    SessionData setupResp = responseData;
    if (setupResp.secVer != SecSchemeVersion.SecScheme1) {
      throw Exception('Invalid sec scheme');
    }
    devicePublicKey = SimplePublicKey(
      setupResp.sec1.sr0.devicePubkey,
      type: x25519.keyPairType,
    );
    deviceRandom = setupResp.sec1.sr0.deviceRandom;

    _verbose(
      'setup0Response:Device public key ${devicePublicKey!.bytes.toString()}',
    );
    _verbose('setup0Response:Device random ${deviceRandom.toString()}');
    return setupResp;
  }

  Future<SessionData> setup1Request(SessionData responseData) async {
    _verbose('setup1Request');
    var setupRequest = SessionData();
    setupRequest.secVer = SecSchemeVersion.SecScheme1;
    SessionCmd1 sc1 = SessionCmd1();
    sc1.clientVerifyData = _xor(
      deviceRandom!,
      await sha256
          .hash(
            await clientKey!.extractPublicKey().then((value) => value.bytes),
          )
          .then((h) => h.bytes),
    );
    Sec1Payload sec1 = Sec1Payload();
    sec1.sc1 = sc1;
    setupRequest.sec1 = sec1;
    return setupRequest;
  }

  Future<void> setup1Response(SessionData responseData) async {
    _verbose('setup1Response');
    // No-op for now
  }
}
