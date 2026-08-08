import 'package:app_polyp/features/legal/widgets/legal_section_card.dart';
import 'package:app_polyp/shared/widgets/research_disclaimer.dart';
import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Điều khoản sử dụng')),
      body: SafeArea(
        child: ListView(
          key: const Key('mobile-terms-screen'),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: const [
            Text(
              'Điều khoản sử dụng ứng dụng mobile',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'Các điều khoản này áp dụng cho phiên bản PolypVision Mobile '
              'kết nối trực tiếp tới dịch vụ AI đã cấu hình.',
            ),
            SizedBox(height: 18),
            LegalSectionCard(
              title: '1. Giới thiệu và phạm vi sử dụng',
              children: [
                Text(
                  'PolypVision là ứng dụng nghiên cứu hỗ trợ phân đoạn polyp '
                  'từ ảnh nội soi đại trực tràng.',
                ),
                SizedBox(height: 10),
                LegalBulletList(
                  items: [
                    'Nghiên cứu và học tập.',
                    'Minh họa hoạt động của mô hình AI.',
                    'Đánh giá kỹ thuật trong môi trường nghiên cứu.',
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  'Ứng dụng không phải công cụ chẩn đoán lâm sàng và không '
                  'được dùng thay cho quy trình chuyên môn.',
                ),
              ],
            ),
            SizedBox(height: 14),
            LegalSectionCard(
              title: '2. Người dùng',
              children: [
                Text(
                  'Phiên bản mobile hiện tại không yêu cầu đăng ký, đăng nhập, '
                  'tài khoản hoặc hồ sơ cá nhân.',
                ),
              ],
            ),
            SizedBox(height: 14),
            LegalSectionCard(
              title: '3. Dữ liệu đầu vào',
              children: [
                Text(
                  'Người dùng chủ động chọn ảnh nội soi từ thư viện ảnh của '
                  'thiết bị. Ảnh được gửi tới FastAPI tại AI_BASE_URL đã cấu '
                  'hình để xử lý bằng mô hình AI.',
                ),
                SizedBox(height: 10),
                Text(
                  'Ứng dụng mobile không tạo lịch sử hoặc lưu lâu dài ảnh và '
                  'overlay. Chính sách lưu giữ phía dịch vụ AI phụ thuộc môi '
                  'trường triển khai; ứng dụng không khẳng định server xóa ảnh '
                  'ngay sau xử lý.',
                ),
              ],
            ),
            SizedBox(height: 14),
            LegalSectionCard(
              title: '4. Kết quả AI',
              children: [
                Text('Kết quả có thể bao gồm:'),
                SizedBox(height: 10),
                LegalBulletList(
                  items: [
                    'Vùng phân đoạn và ảnh overlay.',
                    'Trạng thái phát hiện và nhãn dự đoán.',
                    'Độ tin cậy của dự đoán.',
                    'Số vùng phân đoạn và thời gian xử lý.',
                    'Thông tin mô hình Baseline hoặc VMamba integration.',
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  'Các thông tin này chỉ có ý nghĩa nghiên cứu và tham khảo.',
                ),
              ],
            ),
            SizedBox(height: 14),
            LegalSectionCard(
              title: '5. Hành vi không được phép',
              children: [
                LegalBulletList(
                  items: [
                    'Gửi dữ liệu trái pháp luật hoặc xâm phạm quyền của người khác.',
                    'Cố ý gây hại, làm gián đoạn hoặc tấn công dịch vụ.',
                    'Sử dụng kết quả như chẩn đoán y tế chính thức hoặc cơ sở duy nhất cho điều trị.',
                    'Reverse engineering trái phép hoặc vượt quá phạm vi nghiên cứu được cho phép.',
                  ],
                ),
              ],
            ),
            SizedBox(height: 14),
            LegalSectionCard(
              title: '6. Giới hạn trách nhiệm',
              children: [
                Text(
                  'Hệ thống không bảo đảm kết quả luôn đúng, luôn phát hiện '
                  'polyp, không có false positive hoặc false negative, hay dịch '
                  'vụ luôn hoạt động liên tục. Người dùng chịu trách nhiệm sử '
                  'dụng kết quả đúng phạm vi nghiên cứu.',
                ),
              ],
            ),
            SizedBox(height: 14),
            LegalSectionCard(
              title: '7. Thay đổi dịch vụ và phiên bản tương lai',
              children: [
                Text(
                  'Mô hình, giao diện, API và tính năng nghiên cứu có thể được '
                  'cập nhật. Trong tương lai ứng dụng có thể bổ sung tài khoản, '
                  'đồng bộ dữ liệu hoặc lịch sử phân tích; Điều khoản và Chính '
                  'sách quyền riêng tư sẽ được cập nhật trước khi các chức năng '
                  'đó được đưa vào sử dụng.',
                ),
              ],
            ),
            SizedBox(height: 18),
            ResearchDisclaimer(),
          ],
        ),
      ),
    );
  }
}
