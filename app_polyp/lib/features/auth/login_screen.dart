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

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_formKey.currentState!.validate()) return;
    final success = await ref
        .read(authControllerProvider.notifier)
        .login(
          LoginRequest(
            email: _emailController.text,
            password: _passwordController.text,
          ),
        );
    if (success) {
      _passwordController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    if (_emailController.text.isEmpty && auth.emailHint != null) {
      _emailController.text = auth.emailHint!;
    }
    final isSubmitting = auth.status == AuthStatus.authenticating;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 40,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.blur_circular,
                          size: 54,
                          color: Theme.of(context).colorScheme.primary,
                          semanticLabel: 'Biểu tượng PolypVision',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'PolypVision',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Đăng nhập để tiếp tục không gian nghiên cứu',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.appColors.muted),
                        ),
                        if (auth.status == AuthStatus.unauthenticated &&
                            auth.message != null) ...[
                          const SizedBox(height: 14),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              auth.message!,
                              key: const Key('login-session-message'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        AppCard(
                          semanticLabel: 'Biểu mẫu đăng nhập',
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  key: const Key('login-email'),
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    prefixIcon: Icon(Icons.email_outlined),
                                  ),
                                  validator: (value) {
                                    final email = value?.trim() ?? '';
                                    if (email.isEmpty) {
                                      return 'Vui lòng nhập email.';
                                    }
                                    if (!email.contains('@')) {
                                      return 'Email chưa đúng định dạng.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  key: const Key('login-password'),
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: 'Mật khẩu',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword
                                          ? 'Hiện mật khẩu'
                                          : 'Ẩn mật khẩu',
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (value) =>
                                      (value == null || value.isEmpty)
                                      ? 'Vui lòng nhập mật khẩu.'
                                      : null,
                                ),
                                const SizedBox(height: 18),
                                if (auth.status == AuthStatus.failure &&
                                    !auth.bootstrapFailure) ...[
                                  Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      auth.message ??
                                          'Đã xảy ra lỗi, vui lòng thử lại.',
                                      key: const Key('login-error'),
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                  ),
                                  if (auth.requestId != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Mã yêu cầu: ${auth.requestId}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                ],
                                FilledButton.icon(
                                  key: const Key('login-submit'),
                                  onPressed: isSubmitting ? null : _submit,
                                  icon: isSubmitting
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.login),
                                  label: Text(
                                    isSubmitting
                                        ? 'Đang đăng nhập…'
                                        : 'Đăng nhập',
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextButton(
                                  onPressed: () =>
                                      context.go(AppRoutes.register),
                                  child: const Text(
                                    'Chưa có tài khoản? Đăng ký',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () => context.push(AppRoutes.terms),
                              child: const Text('Điều khoản'),
                            ),
                            TextButton(
                              onPressed: () => context.push(AppRoutes.privacy),
                              child: const Text('Quyền riêng tư'),
                            ),
                          ],
                        ),
                        const ResearchDisclaimer(compact: true),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
