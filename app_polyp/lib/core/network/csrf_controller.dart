import 'package:app_polyp/core/network/api_client.dart';
import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/csrf_token.dart';

class CsrfController {
  CsrfController(this._client);

  final ApiClient _client;
  CsrfToken? _token;
  Future<CsrfToken>? _pendingFetch;

  CsrfToken? get token => _token;

  Future<CsrfToken> fetch() {
    final pending = _pendingFetch;
    if (pending != null) return pending;

    final request = _fetch();
    _pendingFetch = request;
    return request.whenComplete(() => _pendingFetch = null);
  }

  Future<CsrfToken> ensure() async => _token ?? await fetch();

  Future<CsrfToken> _fetch() async {
    try {
      final json = await _client.getJson('/api/v1/auth/csrf');
      final parsed = CsrfToken.fromJson(json);
      _token = parsed;
      return parsed;
    } on FormatException {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'Máy chủ trả về phản hồi không hợp lệ.',
      );
    }
  }

  void clear() => _token = null;
}
