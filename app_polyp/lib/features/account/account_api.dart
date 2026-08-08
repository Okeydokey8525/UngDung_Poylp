import 'package:app_polyp/core/network/api_client.dart';
import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/csrf_controller.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/features/account/account_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class AccountRepository {
  Future<ProfileUpdateResult> updateProfile(ProfileUpdateRequest request);
  Future<void> changePassword(PasswordChangeRequest request);
}

class AccountApi implements AccountRepository {
  const AccountApi(this._client, this._csrf);

  final ApiClient _client;
  final CsrfController _csrf;

  @override
  Future<ProfileUpdateResult> updateProfile(
    ProfileUpdateRequest request,
  ) async {
    await _csrf.ensure();
    final json = await _client.patchJson('/api/v1/me', data: request.toJson());
    try {
      return ProfileUpdateResult.fromJson(json);
    } on FormatException {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'Máy chủ trả về phản hồi không hợp lệ.',
      );
    }
  }

  @override
  Future<void> changePassword(PasswordChangeRequest request) async {
    await _csrf.ensure();
    await _client.putNoContent('/api/v1/me/password', data: request.toJson());
  }
}

final accountApiProvider = Provider<AccountRepository>(
  (ref) => AccountApi(
    ref.watch(apiClientProvider),
    ref.watch(csrfControllerProvider),
  ),
);
