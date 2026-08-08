import 'package:app_polyp/shared/widgets/research_disclaimer.dart';
import 'package:flutter/material.dart';

class InvalidConfigurationScreen extends StatelessWidget {
  const InvalidConfigurationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: 'Cảnh báo cấu hình kết nối',
                    child: Icon(
                      Icons.settings_ethernet_rounded,
                      size: 64,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Cấu hình kết nối không hợp lệ',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Ứng dụng chưa được cấu hình máy chủ HTTPS hợp lệ. '
                    'Vui lòng liên hệ người quản trị hoặc cài lại bản dựng đã '
                    'được cấu hình đúng.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  const ResearchDisclaimer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
