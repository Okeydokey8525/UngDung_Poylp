import 'package:app_polyp/app/app_colors.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/auth/auth_models.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:app_polyp/navigation/app_routes.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:app_polyp/shared/widgets/research_disclaimer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _acceptedTerms = false;
  bool _showTermsError = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final valid = _formKey.currentState!.validate();
    setState(() => _showTermsError = !_acceptedTerms);
    if (!valid || !_acceptedTerms) return;
    final success = await ref
        .read(authControllerProvider.notifier)
        .register(
          RegisterRequest(
            fullName: _fullNameController.text,
            email: _emailController.text,
            password: _passwordController.text,
            confirmPassword: _confirmationController.text,
            acceptedTerms: _acceptedTerms,
          ),
        );
    if (!success || !mounted) return;
    final message =
        ref.read(authControllerProvider).message ?? 'Đăng ký thành công.';
    _passwordController.clear();
    _confirmationController.clear();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$message Vui lòng đăng nhập.')));
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final isSubmitting = auth.status == AuthStatus.authenticating;
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng ký')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tạo tài khoản PolypVision',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tài khoản được bảo vệ bằng phiên đăng nhập của máy chủ.',
                    style: TextStyle(color: context.appColors.muted),
                  ),
                  const SizedBox(height: 18),
                  AppCard(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            key: const Key('register-full-name'),
                            controller: _fullNameController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Họ và tên',
                              prefixIcon: Icon(Icons.person_outline),
                            ).copyWith(errorText: auth.fieldErrors['fullName']),
                            validator: (value) =>
                                (value?.trim().length ?? 0) < 2
                                ? 'Vui lòng nhập họ tên hợp lệ.'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('register-email'),
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ).copyWith(errorText: auth.fieldErrors['email']),
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              if (email.isEmpty) return 'Vui lòng nhập email.';
                              if (!email.contains('@')) {
                                return 'Email chưa đúng định dạng.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('register-password'),
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Mật khẩu',
                              prefixIcon: const Icon(Icons.lock_outline),
                              errorText: auth.fieldErrors['password'],
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Hiện mật khẩu'
                                    : 'Ẩn mật khẩu',
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (value) => (value?.length ?? 0) < 8
                                ? 'Mật khẩu cần ít nhất 8 ký tự.'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('register-confirm-password'),
                            controller: _confirmationController,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            decoration:
                                const InputDecoration(
                                  labelText: 'Xác nhận mật khẩu',
                                  prefixIcon: Icon(Icons.lock_reset_outlined),
                                ).copyWith(
                                  errorText:
                                      auth.fieldErrors['confirmPassword'],
                                ),
                            validator: (value) =>
                                value != _passwordController.text
                                ? 'Mật khẩu xác nhận chưa khớp.'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          CheckboxListTile(
                            value: _acceptedTerms,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text(
                              'Tôi đồng ý với Điều khoản sử dụng.',
                            ),
                            subtitle: _showTermsError
                                ? Text(
                                    'Bạn cần đồng ý trước khi đăng ký.',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  )
                                : null,
                            onChanged: isSubmitting
                                ? null
                                : (value) => setState(
                                    () => _acceptedTerms = value ?? false,
                                  ),
                          ),
                          if (auth.fieldErrors['acceptedTerms'] != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                auth.fieldErrors['acceptedTerms']!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          Wrap(
                            children: [
                              TextButton(
                                onPressed: () => context.push(AppRoutes.terms),
                                child: const Text('Xem Điều khoản'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    context.push(AppRoutes.privacy),
                                child: const Text('Quyền riêng tư'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (auth.status == AuthStatus.failure &&
                              !auth.bootstrapFailure) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                auth.message ??
                                    'Đã xảy ra lỗi, vui lòng thử lại.',
                                key: const Key('register-error'),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                            if (auth.requestId != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Mã yêu cầu: ${auth.requestId}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            const SizedBox(height: 12),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              key: const Key('register-submit'),
                              onPressed: isSubmitting ? null : _submit,
                              child: Text(
                                isSubmitting ? 'Đang đăng ký…' : 'Đăng ký',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.login),
                    child: const Text('Đã có tài khoản? Đăng nhập'),
                  ),
                  const ResearchDisclaimer(compact: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
