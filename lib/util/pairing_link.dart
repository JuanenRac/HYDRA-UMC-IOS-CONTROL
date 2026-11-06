// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - util/pairing_link.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// The code lives in the shared package of the SDK (clients/dart_app_common): the reading of the link the admin page of
// the server puts in its QR code (host, port, SHA-256 fingerprint of the certificate and a name). The fingerprint is
// required (unlike the Android app, which still accepts a link without one). test/shared_package_test.dart checks that the
// limits of the package are the ones of the generated command contract.
// =============================================================================

export 'package:hydra_umc_app_common/hydra_umc_app_common.dart' show PairingLimits, PairingLink, PairingOffer, PairingProblem, PairingResult;
