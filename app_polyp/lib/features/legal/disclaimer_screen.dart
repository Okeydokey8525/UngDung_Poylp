import 'package:app_polyp/features/legal/widgets/legal_section_card.dart';
import 'package:app_polyp/shared/widgets/research_disclaimer.dart';
import 'package:flutter/material.dart';

class DisclaimerScreen extends StatelessWidget {
  const DisclaimerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tuyên bố miễn trừ')),
      body: SafeArea(
        child: ListView(
          key: const Key('mobile-disclaimer-screen'),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: const [
            Text(
              'Giới hạn sử dụng kết quả AI',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 18),
            ResearchDisclaimer(),
            SizedBox(height: 14),
            LegalSectionCard(
              title: 'Khả năng sai lệch',
              children: [
                LegalBulletList(
                  items: [
                    'Hệ thống có thể bỏ sót vùng polyp (false negative).',
                    'Hệ thống có thể đánh dấu nhầm vùng không phải polyp (false positive).',
                    'Kết quả từ một ảnh không đủ để kết luận tình trạng y tế.',
                  ],
                ),
              ],
            ),
            SizedBox(height: 14),
            LegalSectionCard(
              title: 'Cách hiểu confidence',
              children: [
                Text(
                  'Confidence được hiển thị là Độ tin cậy của dự đoán do mô '
                  'hình trả về. Giá trị này không phải xác suất mắc bệnh và '
                  'không chứng minh kết quả đúng trong một ca cụ thể.',
                ),
              ],
            ),
            SizedBox(height: 14),
            LegalSectionCard(
              title: 'Trách nhiệm đánh giá y khoa',
              children: [
                Text(
                  'Việc đánh giá y khoa phải do nhân viên y tế có chuyên môn '
                  'thực hiện dựa trên đầy đủ thông tin lâm sàng. Không sử dụng '
                  'kết quả PolypVision làm cơ sở duy nhất cho quyết định điều '
                  'trị hoặc can thiệp y tế.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
