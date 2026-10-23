// =============================================================================
// HYDRA-UMC-IOS-CONTROL - Address of the embedded 3D viewer
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
// =============================================================================

/// Builds the address the embedded 3D viewer loads. The access token goes in the
/// fragment (`#token=...`): a fragment is never sent to the server, so no access log,
/// proxy or referrer ever sees it. The viewer reads it from there and drops it from the
/// address.
class ViewerUrl {
  const ViewerUrl._();

  /// Address of the viewer for [robotId] on [base] (the scheme the client learned, so
  /// https for a TLS server). [token] may be empty: the viewer then asks for a login.
  static Uri build(Uri base, int robotId, String? token) {
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/',
      queryParameters: {'hideUI': 'true', 'robotId': '$robotId'},
      fragment: (token == null || token.isEmpty) ? null : 'token=${Uri.encodeQueryComponent(token)}',
    );
  }
}
