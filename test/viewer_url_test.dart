// =============================================================================
// HYDRA-UMC-IOS-CONTROL - Address of the embedded 3D viewer, test
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_umc_control/util/viewer_url.dart';

void main() {
  test('the token travels in the fragment and never in the query', () {
    final uri = ViewerUrl.build(Uri.parse('http://192.168.1.20:3000'), 2, 'abc.def.ghi');
    expect(uri.queryParameters.containsKey('token'), isFalse);
    expect(uri.query, 'hideUI=true&robotId=2');
    expect(uri.fragment, 'token=abc.def.ghi');
    expect(uri.toString(), 'http://192.168.1.20:3000/?hideUI=true&robotId=2#token=abc.def.ghi');
  });

  test('the scheme the client learned is kept and a token with odd characters is encoded', () {
    final uri = ViewerUrl.build(Uri.parse('https://hydra.local:3443'), 7, 'a+b/c?d=e&f');
    expect(uri.scheme, 'https');
    expect(uri.port, 3443);
    expect(uri.query.contains('a+b'), isFalse);
    expect(uri.queryParameters.containsKey('token'), isFalse);
    final decoded = Uri.splitQueryString(uri.fragment);
    expect(decoded['token'], 'a+b/c?d=e&f');
  });

  test('without a token the address has no fragment, so the viewer asks for a login', () {
    expect(ViewerUrl.build(Uri.parse('http://h:3000'), 1, null).hasFragment, isFalse);
    expect(ViewerUrl.build(Uri.parse('http://h:3000'), 1, '').hasFragment, isFalse);
  });
}
