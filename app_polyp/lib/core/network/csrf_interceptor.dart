import 'package:app_polyp/core/network/csrf_token.dart';
import 'package:dio/dio.dart';

class CsrfInterceptor extends Interceptor {
  CsrfInterceptor(this._currentToken);

  final CsrfToken? Function() _currentToken;

  static const _unsafeMethods = {'POST', 'PUT', 'PATCH', 'DELETE'};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_unsafeMethods.contains(options.method.toUpperCase())) {
      final csrf = _currentToken();
      if (csrf != null) {
        options.headers[csrf.headerName] = csrf.token;
      }
    }
    handler.next(options);
  }
}
