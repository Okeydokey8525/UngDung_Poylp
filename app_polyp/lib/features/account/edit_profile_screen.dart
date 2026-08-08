import 'package:app_polyp/features/account/account_controller.dart';
import 'package:app_polyp/features/account/account_models.dart';
import 'package:app_polyp/features/account/account_state.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    _fullNameController = TextEditingController(text: user?.fullName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    Future<void>.microtask(
      ref.read(accountControllerProvider.notifier).clearFeedback,
    );
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    ref.read(accountControllerProvider.notifier).clearFeedback();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final outcome = await ref
        .read(accountControllerProvider.notifier)
        .updateProfile(
          ProfileUpdateRequest(
            fullName: _fullNameController.text,
            email: _emailController.text,
          ),
        );
    if (!mounted || outcome == null) return;
    if (outcome == ProfileUpdateOutcome.updated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cập nhật hồ sơ thành công.')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final operation = ref.watch(accountControllerProvider);
    final submitting = operation.isSubmitting;
    final serverFullNameError = operation.fieldErrors['fullName'];
    final serverEmailError = operation.fieldErrors['email'];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Sửa hồ sơ', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Cập nhật tên hiển thị hoặc địa chỉ email của tài khoản.'),
        const SizedBox(height: 18),
        AppCard(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('profile-full-name'),
                  controller: _fullNameController,
                  enabled: !submitting,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: InputDecoration(
                    labelText: 'Họ và tên',
                    errorText: serverFullNameError,
                  ),
                  validator: (value) {
                    final length = value?.trim().length ?? 0;
                    if (length < 2 || length > 100) {
                      return 'Họ tên phải có từ 2 đến 100 ký tự.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('profile-email'),
                  controller: _emailController,
                  enabled: !submitting,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: 'Email',
                    helperText:
                        'Đổi email sẽ kết thúc phiên để bảo vệ tài khoản.',
                    errorText: serverEmailError,
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty ||
                        !RegExp(
                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                        ).hasMatch(email)) {
                      return 'Email chưa đúng định dạng.';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) {
                    if (!submitting) _submit();
                  },
                ),
                if (operation.status == AccountOperationStatus.failure) ...[
                  const SizedBox(height: 14),
                  Text(
                    operation.message ?? 'Không thể cập nhật hồ sơ.',
                    key: const Key('profile-error'),
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
                  key: const Key('profile-submit'),
                  onPressed: submitting ? null : _submit,
                  child: submitting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Lưu thay đổi'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
