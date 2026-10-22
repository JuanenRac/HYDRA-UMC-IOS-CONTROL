// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/discovery_interfaces_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// Which network interfaces the subnet scan sweeps: all of them by default, and
// without the mobile-data and VPN ones when the operator asks for that.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:hydra_umc_control/network/discovery.dart';

void main() {
  const interfaces = {
    'en0': ['192.168.0.23'],
    'pdp_ip0': ['10.64.12.5'],
    'utun3': ['10.8.0.2'],
    'bridge100': ['172.20.10.1'],
  };

  test('names of mobile-data and VPN interfaces are recognised', () {
    for (final name in ['pdp_ip0', 'pdp_ip1', 'utun0', 'utun4', 'ipsec0', 'ppp0', 'tun0', 'wg0', 'rmnet_data0', 'UTUN1']) {
      expect(isMobileOrVpnInterface(name), isTrue, reason: name);
    }
    for (final name in ['en0', 'en1', 'bridge100', 'lo0', 'eth0', 'wlan0', 'awdl0']) {
      expect(isMobileOrVpnInterface(name), isFalse, reason: name);
    }
  });

  test('by default every interface is swept', () {
    expect(
      prefixesOfInterfaces(interfaces),
      {'192.168.0', '10.64.12', '10.8.0', '172.20.10'},
    );
  });

  test('with the switch on, mobile-data and VPN interfaces are left out', () {
    expect(
      prefixesOfInterfaces(interfaces, skipMobileAndVpn: true),
      {'192.168.0', '172.20.10'},
    );
  });

  test('an address that is not four parts is ignored', () {
    expect(prefixesOfInterfaces({'en0': ['fe80::1', '10.0.0.5']}), {'10.0.0'});
  });
}
