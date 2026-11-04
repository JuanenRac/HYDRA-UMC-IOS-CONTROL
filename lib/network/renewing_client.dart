// =============================================================================
// HYDRA-UMC CONTROL (iOS/Flutter) - network/renewing_client.dart
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D) <electrohobby3d@gmail.com>
// GPL-3.0-or-later - see LICENSE
//
// An interceptor over http.Client: a request that carried a bearer token and
// was answered with an expired or invalid session (401, or 403 TOKEN_EXPIRED /
// TOKEN_INVALID) asks the owner of the session for a new token and is sent
// once more with it. Any other answer, a request without a bearer token (login,
// refresh) and a failed renewal reach the caller untouched. Only requests with
// a body already in memory (http.Request) are repeated; a streamed upload is
// passed through as it is.
// =============================================================================

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Returns the new bearer token, or null when the session could not be renewed.
typedef TokenRenewer = Future<String?> Function();

class RenewingClient extends http.BaseClient {
  RenewingClient(this._inner, this._renewer);

  final http.Client _inner;

  /// Read at every request, so the owner can set it after the client exists
  /// (and clear it when the session ends).
  final TokenRenewer? Function() _renewer;

  /// True for the answers a new token can cure.
  static bool isSessionAnswer(int status, String body) {
    if (status == 401) return true;
    if (status != 403) return false;
    try {
      final decoded = jsonDecode(body);
      final code = decoded is Map ? decoded['code'] : null;
      return code == 'TOKEN_EXPIRED' || code == 'TOKEN_INVALID';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final renewer = _renewer();
    final hadBearer = (request.headers['Authorization'] ?? '').startsWith('Bearer ');
    if (renewer == null || !hadBearer || request is! http.Request) return _inner.send(request);

    final first = await _inner.send(request);
    if (first.statusCode != 401 && first.statusCode != 403) return first;

    final bytes = await first.stream.toBytes();
    final body = utf8.decode(bytes, allowMalformed: true);
    if (!isSessionAnswer(first.statusCode, body)) return _replay(first, bytes);

    String? token;
    try {
      token = await renewer();
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) return _replay(first, bytes);

    final again = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..headers['Authorization'] = 'Bearer $token'
      ..bodyBytes = request.bodyBytes
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;
    return _inner.send(again);
  }

  http.StreamedResponse _replay(http.StreamedResponse r, List<int> bytes) => http.StreamedResponse(
        Stream.value(bytes),
        r.statusCode,
        contentLength: bytes.length,
        request: r.request,
        headers: r.headers,
        isRedirect: r.isRedirect,
        persistentConnection: r.persistentConnection,
        reasonPhrase: r.reasonPhrase,
      );

  @override
  void close() => _inner.close();
}
