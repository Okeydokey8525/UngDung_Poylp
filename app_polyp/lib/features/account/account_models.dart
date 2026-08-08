import 'package:app_polyp/features/auth/auth_models.dart';

class ProfileUpdateRequest {
  const ProfileUpdateRequest({required this.fullName, required this.email});

  final String fullName;
  final String email;

  Map<String, dynamic> toJson() => {
    'fullName': fullName.trim(),
    'email': email.trim().toLowerCase(),
  };
}

class ProfileUpdateResult {
  const ProfileUpdateResult({
    required this.user,
    required this.reauthenticationRequired,
  });

  factory ProfileUpdateResult.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    if (rawUser is! Map) {
      throw const FormatException('Invalid profile response');
    }
    return ProfileUpdateResult(
      user: AuthUser.fromJson(Map<String, dynamic>.from(rawUser)),
      reauthenticationRequired: json['reauthenticationRequired'] == true,
    );
  }

  final AuthUser user;
  final bool reauthenticationRequired;
}

class PasswordChangeRequest {
  const PasswordChangeRequest({
    required this.currentPassword,
    required this.newPassword,
    required this.confirmPassword,
  });

  final String currentPassword;
  final String newPassword;
  final String confirmPassword;

  Map<String, dynamic> toJson() => {
    'currentPassword': currentPassword,
    'newPassword': newPassword,
    'confirmPassword': confirmPassword,
  };
}

enum ProfileUpdateOutcome { updated, reauthenticationRequired }
