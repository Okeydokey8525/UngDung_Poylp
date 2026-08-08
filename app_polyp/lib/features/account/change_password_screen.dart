import 'package:app_polyp/features/account/account_controller.dart';
import 'package:app_polyp/features/account/account_models.dart';
import 'package:app_polyp/features/account/account_state.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmation = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      ref.read(accountControllerProvider.notifier).clearFeedback,
    );
  }

  @override
  void dispose() {
    _clearPasswords();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _clearPasswords() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmationController.clear();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    ref.read(accountControllerProvider.notifier).clearFeedback();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final request = PasswordChangeRequest(
      currentPassword: _currentPasswordController.text,
      newPassword: _newPasswordController.text,
      confirmPassword: _confirmationController.text,
    );
    try {
      await ref
          .read(accountControllerProvider.notifier)
          .changePassword(request);
    } finally {
      if (mounted) {
        setState(_clearPasswords);
      } else {
        _clearPasswords();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final operation = ref.watch(accountControllerProvider);
    final submitting = operation.isSubmitting;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Đổi mật khẩu', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Sau khi đổi thành công, bạn cần đăng nhập lại bằng mật khẩu mới.',
        ),
        const SizedBox(height: 18),
        AppCard(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('password-current'),
                  controller: _currentPasswordController,
                  enabled: !submitting,
                  obscureText: !_showCurrentPassword,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu hiện tại',
                    errorText: operation.fieldErrors['currentPassword'],
                    suffixIcon: IconButton(
                      tooltip: _showCurrentPassword
                          ? 'Ẩn mật khẩu hiện tại'
                          : 'Hiện mật khẩu hiện tại',
                      onPressed: () => setState(
                        () => _showCurrentPassword = !_showCurrentPassword,
                      ),
                      icon: Icon(
                        _showCurrentPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => (value?.isEmpty ?? true)
                      ? 'Vui lòng nhập mật khẩu hiện tại.'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('password-new'),
                  controller: _newPasswordController,
                  enabled: !submitting,
                  obscureText: !_showNewPassword,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu mới',
                    helperText:
                        'Dùng 8–72 ký tự, gồm ít nhất một chữ và một số.',
                    errorText: operation.fieldErrors['newPassword'],
                    suffixIcon: IconButton(
                      tooltip: _showNewPassword
                          ? 'Ẩn mật khẩu mới'
                          : 'Hiện mật khẩu mới',
                      onPressed: () =>
                          setState(() => _showNewPassword = !_showNewPassword),
                      icon: Icon(
                        _showNewPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final password = value ?? '';
                    if (password.length < 8 || password.length > 72) {
                      return 'Mật khẩu phải có từ 8 đến 72 ký tự.';
                    }
                    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
                        !RegExp(r'\d').hasMatch(password)) {
                      return 'Mật khẩu cần có ít nhất một chữ và một số.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('password-confirmation'),
                  controller: _confirmationController,
                  enabled: !submitting,
                  obscureText: !_showConfirmation,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Xác nhận mật khẩu mới',
                    errorText: operation.fieldErrors['confirmPassword'],
                    suffixIcon: IconButton(
                      tooltip: _showConfirmation
                          ? 'Ẩn xác nhận mật khẩu'
                          : 'Hiện xác nhận mật khẩu',
                      onPressed: () => setState(
                        () => _showConfirmation = !_showConfirmation,
                      ),
                      icon: Icon(
                        _showConfirmation
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => value != _newPasswordController.text
                      ? 'Mật khẩu xác nhận chưa khớp.'
                      : null,
                  onFieldSubmitted: (_) {
                    if (!submitting) _submit();
                  },
                ),
                if (operation.status == AccountOperationStatus.failure) ...[
                  const SizedBox(height: 14),
                  Text(
                    operation.message ?? 'Không thể đổi mật khẩu.',
                    key: const Key('password-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (operation.requestId != null)
                    Text(
                      'Mã yêu cầu: ${operation.requestId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  key: const Key('password-submit'),
                  onPressed: submitting ? null : _submit,
                  child: submitting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Đổi mật khẩu'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
