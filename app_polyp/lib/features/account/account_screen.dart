import 'package:app_polyp/app/app_colors.dart';
import 'package:app_polyp/app/theme_controller.dart';
import 'package:app_polyp/core/config/app_config.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/navigation/app_routes.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:app_polyp/shared/widgets/app_loading_view.dart';
import 'package:app_polyp/shared/widgets/app_section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    final themePreference = ref.watch(themeControllerProvider);

    if (user == null) {
      return const AppLoadingView(message: 'Đang tải thông tin tài khoản…');
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const AppSectionHeader(
          title: 'Tài khoản',
          subtitle: 'Thông tin tài khoản hiện tại từ máy chủ PolypVision.',
        ),
        const SizedBox(height: 18),
        AppCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: context.appColors.primarySoft,
                foregroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  user.initials,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(user.email),
                    const SizedBox(height: 4),
                    Chip(label: Text(user.role)),
                    if (user.createdAt != null)
                      Text(
                        'Tham gia: ${_formatDate(user.createdAt!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Sửa hồ sơ'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.editProfile),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: const Text('Đổi mật khẩu'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.changePassword),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Giao diện', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              RadioGroup<AppThemePreference>(
                groupValue: themePreference,
                onChanged: (value) {
                  if (value != null) {
                    ref
                        .read(themeControllerProvider.notifier)
                        .setPreference(value);
                  }
                },
                child: Column(
                  children: [
                    for (final preference in AppThemePreference.values)
                      RadioListTile<AppThemePreference>(
                        key: Key('theme-${preference.name}'),
                        value: preference,
                        title: Text(preference.label),
                        secondary: Icon(switch (preference) {
                          AppThemePreference.system =>
                            Icons.settings_brightness,
                          AppThemePreference.light => Icons.light_mode_outlined,
                          AppThemePreference.dark => Icons.dark_mode_outlined,
                        }),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              _AccountLink(
                icon: Icons.info_outline,
                label: 'Giới thiệu',
                route: AppRoutes.about,
              ),
              _AccountLink(
                icon: Icons.privacy_tip_outlined,
                label: 'Quyền riêng tư',
                route: AppRoutes.privacy,
              ),
              _AccountLink(
                icon: Icons.gavel_outlined,
                label: 'Điều khoản',
                route: AppRoutes.terms,
              ),
              _AccountLink(
                icon: Icons.health_and_safety_outlined,
                label: 'Tuyên bố miễn trừ',
                route: AppRoutes.disclaimer,
              ),
            ],
          ),
        ),
        if (AppConfig.showDebugInfo) ...[
          const SizedBox(height: 14),
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.bug_report_outlined,
                  color: context.appColors.warning,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Debug API base URL\n${AppConfig.apiBaseUrl}\n\n'
                    'Cookie phiên chỉ lưu trong bộ nhớ; đóng hẳn ứng dụng '
                    'sẽ cần đăng nhập lại.',
                    key: const Key('debug-api-base-url'),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          key: const Key('logout-button'),
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Đăng xuất?'),
                content: const Text(
                  'Phiên đăng nhập trên thiết bị này sẽ bị xóa.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Hủy'),
                  ),
                  FilledButton(
                    key: const Key('confirm-logout'),
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Đăng xuất'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              await ref.read(authControllerProvider.notifier).logout();
            }
          },
          icon: const Icon(Icons.logout),
          label: const Text('Đăng xuất'),
        ),
      ],
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }
}

class _AccountLink extends StatelessWidget {
  const _AccountLink({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(route),
    );
  }
}
