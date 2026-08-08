import 'package:app_polyp/app/app_colors.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:app_polyp/shared/widgets/app_error_state.dart';
import 'package:app_polyp/shared/widgets/app_loading_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(authControllerProvider.notifier).bootstrap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: 'Biểu tượng PolypVision trừu tượng',
                  image: true,
                  child: Image.asset(
                    'assets/branding/splash_logo.png',
                    width: 104,
                    height: 104,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'PolypVision',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Phân đoạn polyp phục vụ nghiên cứu',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.appColors.muted),
                ),
                const SizedBox(height: 32),
                if (auth.status == AuthStatus.failure && auth.bootstrapFailure)
                  AppErrorState(
                    title: 'Không thể kiểm tra phiên đăng nhập',
                    message: auth.message ?? 'Không kết nối được máy chủ.',
                    onRetry: () => ref
                        .read(authControllerProvider.notifier)
                        .bootstrap(force: true),
                  )
                else
                  const AppLoadingView(
                    message: 'Đang kiểm tra phiên đăng nhập…',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
