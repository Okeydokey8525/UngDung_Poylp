import 'package:app_polyp/features/account/account_screen.dart';
import 'package:app_polyp/features/account/change_password_screen.dart';
import 'package:app_polyp/features/account/edit_profile_screen.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:app_polyp/features/auth/login_screen.dart';
import 'package:app_polyp/features/auth/register_screen.dart';
import 'package:app_polyp/features/auth/splash_screen.dart';
import 'package:app_polyp/features/comparison/comparison_result_screen.dart';
import 'package:app_polyp/features/comparison/comparison_screen.dart';
import 'package:app_polyp/features/comparison/comparison_models.dart';
import 'package:app_polyp/features/dashboard/dashboard_screen.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_result_screen.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_models.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_screen.dart';
import 'package:app_polyp/features/diagnosis/fullscreen_image_screen.dart';
import 'package:app_polyp/features/history/history_screen.dart';
import 'package:app_polyp/features/legal/about_screen.dart';
import 'package:app_polyp/features/legal/disclaimer_screen.dart';
import 'package:app_polyp/features/legal/privacy_screen.dart';
import 'package:app_polyp/features/legal/terms_screen.dart';
import 'package:app_polyp/navigation/app_routes.dart';
import 'package:app_polyp/navigation/app_shell.dart';
import 'package:app_polyp/shared/widgets/app_error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier();
  ref.listen<AuthState>(authControllerProvider, (_, _) => refresh.notify());

  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      final isLegal = {
        AppRoutes.about,
        AppRoutes.privacy,
        AppRoutes.terms,
        AppRoutes.disclaimer,
      }.contains(location);
      final isAuthentication = {
        AppRoutes.login,
        AppRoutes.register,
      }.contains(location);

      return switch (auth.status) {
        AuthStatus.checking =>
          location == AppRoutes.splash ? null : AppRoutes.splash,
        AuthStatus.unauthenticated || AuthStatus.authenticating =>
          location == AppRoutes.splash
              ? AppRoutes.login
              : (isAuthentication || isLegal)
              ? null
              : AppRoutes.login,
        AuthStatus.failure =>
          auth.bootstrapFailure
              ? (location == AppRoutes.splash ? null : AppRoutes.splash)
              : location == AppRoutes.splash
              ? AppRoutes.login
              : (isAuthentication || isLegal)
              ? null
              : AppRoutes.login,
        AuthStatus.authenticated =>
          location == AppRoutes.splash || isAuthentication
              ? AppRoutes.dashboard
              : null,
      };
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.dashboard,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.diagnosis,
                builder: (context, state) => const DiagnosisScreen(),
                routes: [
                  GoRoute(
                    path: 'result/:id',
                    builder: (context, state) => DiagnosisResultScreen(
                      id: state.pathParameters['id'] ?? '',
                      initialResult: state.extra is DiagnosisResult
                          ? state.extra! as DiagnosisResult
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.comparison,
                builder: (context, state) => const ComparisonScreen(),
                routes: [
                  GoRoute(
                    path: 'result/:comparisonGroupId',
                    builder: (context, state) => ComparisonResultScreen(
                      comparisonGroupId:
                          state.pathParameters['comparisonGroupId'] ?? '',
                      initialResult: state.extra is ComparisonResult
                          ? state.extra! as ComparisonResult
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.history,
                builder: (context, state) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.account,
                builder: (context, state) => const AccountScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => const EditProfileScreen(),
                  ),
                  GoRoute(
                    path: 'change-password',
                    builder: (context, state) => const ChangePasswordScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.diagnosisImage,
        builder: (context, state) {
          final arguments = state.extra;
          if (arguments is! AuthenticatedImageArguments) {
            return const Scaffold(
              body: AppErrorState(
                title: 'Không thể mở ảnh',
                message: 'Thông tin ảnh không hợp lệ.',
              ),
            );
          }
          return FullscreenImageScreen(arguments: arguments);
        },
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: AppRoutes.privacy,
        builder: (context, state) => const PrivacyScreen(),
      ),
      GoRoute(
        path: AppRoutes.terms,
        builder: (context, state) => const TermsScreen(),
      ),
      GoRoute(
        path: AppRoutes.disclaimer,
        builder: (context, state) => const DisclaimerScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Không tìm thấy trang')),
      body: AppErrorState(
        title: 'Đường dẫn không hợp lệ',
        message: 'Trang bạn yêu cầu không tồn tại hoặc chưa có trong ứng dụng.',
        onRetry: () => context.go(
          ref.read(authControllerProvider).status == AuthStatus.authenticated
              ? AppRoutes.dashboard
              : AppRoutes.login,
        ),
      ),
    ),
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class _RouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
