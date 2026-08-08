class AuthUser {
  const AuthUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.createdAt,
    this.updatedAt,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final fullName = json['fullName'];
    final email = json['email'];
    final role = json['role'];
    if (id is! String ||
        fullName is! String ||
        email is! String ||
        role is! String) {
      throw const FormatException('Invalid user response');
    }

    return AuthUser(
      id: id,
      fullName: fullName,
      email: email,
      role: role,
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  final String id;
  final String fullName;
  final String email;
  final String role;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get initials {
    final words = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'P';
    String firstCharacter(String word) => String.fromCharCode(word.runes.first);
    if (words.length == 1) return firstCharacter(words.first).toUpperCase();
    return '${firstCharacter(words.first)}${firstCharacter(words.last)}'
        .toUpperCase();
  }
}

class LoginRequest {
  const LoginRequest({required this.email, required this.password});

  final String email;
  final String password;

  Map<String, dynamic> toJson() => {
    'email': email.trim().toLowerCase(),
    'password': password,
  };
}

class RegisterRequest {
  const RegisterRequest({
    required this.fullName,
    required this.email,
    required this.password,
    required this.confirmPassword,
    required this.acceptedTerms,
  });

  final String fullName;
  final String email;
  final String password;
  final String confirmPassword;
  final bool acceptedTerms;

  Map<String, dynamic> toJson() => {
    'fullName': fullName.trim(),
    'email': email.trim().toLowerCase(),
    'password': password,
    'confirmPassword': confirmPassword,
    'acceptedTerms': acceptedTerms,
  };
}

class RegisterResult {
  const RegisterResult({required this.message, required this.email});

  factory RegisterResult.fromJson(Map<String, dynamic> json) {
    final message = json['message'];
    final email = json['email'];
    if (message is! String || email is! String) {
      throw const FormatException('Invalid register response');
    }
    return RegisterResult(message: message, email: email);
  }

  final String message;
  final String email;
}
