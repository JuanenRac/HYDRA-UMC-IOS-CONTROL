// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/connection_diagnostics_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The connection diagnostics: which trust applies, the figures of the probes, and a report that never
// carries a secret and never grows past its limit.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/util/connection_diagnostics.dart';
import 'package:hydra_umc_control/util/link_health.dart';

ConnectionDiagnostics _run(List<int?> latencies, {TrustMode trust = TrustMode.pinnedFingerprint, String pinned = 'AB:CD'}) =>
    ConnectionDiagnostics(
      scheme: 'https',
      host: '192.168.0.10',
      port: 3000,
      trust: trust,
      pinnedFingerprint: pinned,
      remoteApiVersion: 2,
      serverAppVersion: '0.8.0',
      clientVersion: '0.8.0',
      latenciesMs: latencies,
      level: LinkLevel.good,
      websocket: 'connected',
      role: 'operator',
    );

void main() {
  test('plain http is never trusted as a certificate, whatever is pinned', () {
    expect(
      ConnectionDiagnostics.trustFor(scheme: 'http', pinnedFingerprint: 'AB', customCaPem: 'PEM'),
      TrustMode.plainHttp,
    );
  });

  test('over https a pinned fingerprint wins over an own authority, and the system store is the last resort', () {
    expect(ConnectionDiagnostics.trustFor(scheme: 'https', pinnedFingerprint: 'AB', customCaPem: 'PEM'), TrustMode.pinnedFingerprint);
    expect(ConnectionDiagnostics.trustFor(scheme: 'https', pinnedFingerprint: '  ', customCaPem: 'PEM'), TrustMode.customAuthority);
    expect(ConnectionDiagnostics.trustFor(scheme: 'https', pinnedFingerprint: '', customCaPem: ' \n'), TrustMode.systemCertificates);
  });

  test('the figures count only the probes that were answered', () {
    final d = _run([10, null, 30, 20, null]);
    expect(d.answeredMs, [10, 30, 20]);
    expect(d.minMs, 10);
    expect(d.maxMs, 30);
    expect(d.averageMs, 20);
    expect(d.lost, 2);
  });

  test('with no answer at all there are no figures and every probe is lost', () {
    final d = _run([null, null, null]);
    expect(d.minMs, isNull);
    expect(d.maxMs, isNull);
    expect(d.averageMs, isNull);
    expect(d.lost, 3);
    expect(d.report(), contains('latency: min none, average none, max none'));
  });

  test('the report names the address, the trust, each probe and the link, and holds no secret', () {
    final text = _run([12, null]).report();
    expect(text, contains('address: https://192.168.0.10:3000'));
    expect(text, contains('trust: pinnedFingerprint'));
    expect(text, contains('pinned fingerprint (SHA-256): AB:CD'));
    expect(text, contains('probes: 2 sent, 1 without answer'));
    expect(text, contains('  probe 1: 12 ms'));
    expect(text, contains('  probe 2: none'));
    expect(text, contains('link level: good'));
    expect(text, contains('session role: operator'));
    expect(text, contains('showing saved data: no'));
    for (final word in ['password', 'token', 'cookie', 'BEGIN CERTIFICATE']) {
      expect(text.toLowerCase(), isNot(contains(word.toLowerCase())), reason: word);
    }
  });

  test('a server that did not say its versions is reported as unknown, and no fingerprint line appears without one', () {
    final d = ConnectionDiagnostics(
      scheme: 'http',
      host: 'robot.local',
      port: 80,
      trust: TrustMode.plainHttp,
      clientVersion: '0.8.0',
    );
    final text = d.report();
    expect(text, contains('server remote API version: unknown'));
    expect(text, contains('server app version: unknown'));
    expect(text, contains('session role: unknown'));
    expect(text, isNot(contains('pinned fingerprint')));
  });

  test('the report never goes past its line limit', () {
    final d = _run(List<int?>.generate(500, (i) => i));
    expect(d.report().split('\n').length, 100);
    expect(d.report(maxLines: 5).split('\n').length, 5);
  });

  test('a probe is answered only when it has a time', () {
    expect(const InfoProbe(rttMs: 0).answered, isTrue);
    expect(const InfoProbe().answered, isFalse);
  });
}
