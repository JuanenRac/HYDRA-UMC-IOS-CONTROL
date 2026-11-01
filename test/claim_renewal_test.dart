// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - test/claim_renewal_test.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// When a reservation held here is asked for again so a long session keeps it.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_umc_control/models/access.dart';

ClaimInfo _claim(int expiresAt) => ClaimInfo(
      robotId: 1,
      robotName: 'A',
      ownerUsername: 'op',
      controllerId: 'c',
      expiresAt: expiresAt,
    );

void main() {
  const now = 1000000;

  test('a reservation held here with little time left is renewed', () {
    expect(claimNeedsRenewal(_claim(now + 60000), ClaimStanding.mineHere, now), isTrue);
    expect(claimNeedsRenewal(_claim(now + claimRenewBeforeMs), ClaimStanding.mineHere, now), isTrue);
  });

  test('a reservation with plenty of time left is left alone', () {
    expect(claimNeedsRenewal(_claim(now + claimRenewBeforeMs + 1), ClaimStanding.mineHere, now), isFalse);
  });

  test('a reservation that already ended is not brought back', () {
    expect(claimNeedsRenewal(_claim(now), ClaimStanding.mineHere, now), isFalse);
    expect(claimNeedsRenewal(_claim(now - 1000), ClaimStanding.mineHere, now), isFalse);
  });

  test('only a reservation held by this installation is renewed', () {
    final soon = _claim(now + 30000);
    expect(claimNeedsRenewal(soon, ClaimStanding.other, now), isFalse);
    expect(claimNeedsRenewal(soon, ClaimStanding.mineElsewhere, now), isFalse);
    expect(claimNeedsRenewal(soon, ClaimStanding.free, now), isFalse);
    expect(claimNeedsRenewal(null, ClaimStanding.mineHere, now), isFalse);
  });

  test('the window to renew can be chosen', () {
    expect(claimNeedsRenewal(_claim(now + 50000), ClaimStanding.mineHere, now, renewBeforeMs: 30000), isFalse);
    expect(claimNeedsRenewal(_claim(now + 20000), ClaimStanding.mineHere, now, renewBeforeMs: 30000), isTrue);
  });
}
