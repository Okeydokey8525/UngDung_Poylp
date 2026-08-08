import 'package:app_polyp/features/analysis/direct_analysis_screen.dart';
import 'package:app_polyp/features/comparison/direct_comparison_screen.dart';
import 'package:app_polyp/features/home/ai_home_screen.dart';
import 'package:app_polyp/features/legal/direct_about_screen.dart';
import 'package:app_polyp/features/legal/disclaimer_screen.dart';
import 'package:app_polyp/features/legal/privacy_screen.dart';
import 'package:app_polyp/features/legal/terms_screen.dart';
import 'package:app_polyp/navigation/direct_ai_app_shell.dart';
import 'package:app_polyp/shared/widgets/app_error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

abstract final class DirectAiRoutes {
  static const home = '/';
  static const analyze = '/analyze';
  static const compare = '/compare';
  static const about = '/about';
  static const privacy = '/privacy';
  static const terms = '/terms';
  static const disclaimer = '/disclaimer';
}

final directAiRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: DirectAiRoutes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            DirectAiAppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: DirectAiRoutes.home,
                builder: (context, state) => const AiHomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: DirectAiRoutes.analyze,
                builder: (context, state) => const DirectAnalysisScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: DirectAiRoutes.compare,
                builder: (context, state) => const DirectComparisonScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: DirectAiRoutes.about,
                builder: (context, state) => const DirectAboutScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: DirectAiRoutes.privacy,
        builder: (context, state) => const PrivacyScreen(),
      ),
      GoRoute(
        path: DirectAiRoutes.terms,
        builder: (context, state) => const TermsScreen(),
      ),
      GoRoute(
        path: DirectAiRoutes.disclaimer,
        builder: (context, state) => const DisclaimerScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Không tìm thấy trang')),
      body: AppErrorState(
        title: 'Đường dẫn không hợp lệ',
        message: 'Trang bạn yêu cầu không tồn tại hoặc chưa có trong ứng dụng.',
        onRetry: () => context.go(DirectAiRoutes.home),
      ),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});
