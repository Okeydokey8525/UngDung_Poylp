class CsrfToken {
  const CsrfToken({
    required this.token,
    required this.headerName,
    required this.parameterName,
  });

  factory CsrfToken.fromJson(Map<String, dynamic> json) {
    final token = json['token'];
    final headerName = json['headerName'];
    final parameterName = json['parameterName'];
    if (token is! String ||
        token.isEmpty ||
        headerName is! String ||
        headerName.isEmpty ||
        parameterName is! String ||
        parameterName.isEmpty) {
      throw const FormatException('Invalid CSRF response');
    }
    return CsrfToken(
      token: token,
      headerName: headerName,
      parameterName: parameterName,
    );
  }

  final String token;
  final String headerName;
  final String parameterName;
}
