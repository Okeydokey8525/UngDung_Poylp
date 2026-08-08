import 'package:app_polyp/features/legal/widgets/legal_section_card.dart';
import 'package:app_polyp/shared/widgets/research_disclaimer.dart';
import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quyền riêng tư')),
      body: SafeArea(
        child: ListView(
          key: const Key('mobile-privacy-screen'),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: const [
            Text(
              'Chính sách quyền riêng tư mobile',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'Chính sách này áp dụng cho PolypVision Mobile Direct AI trong '
              'phiên bản hiện tại.',
            ),
            SizedBox(height: 18),
            LegalSectionCard(
              title: '1. Dữ liệu người dùng chủ động cung cấp',
              children: [
                Text(
                  'Người dùng chủ động chọn ảnh nội soi từ thiết bị. Khi gửi '
                  'yêu cầu phân tích, ứng dụng chuyển ảnh và metadata kỹ thuật '
                  'cần thiết như tên tệp, loại nội dung và kích thước tới FastAPI '
                  'tại AI_BASE_URL đã cấu hình.',
                ),
              ],
            ),
            SizedBox(height: 14),
            LegalSectionCard(
              title: '2. Dữ liệu không thu thập trong phiên bản hiện tại',
              children: [
                LegalBulletList(
                  items: [
                    'Không đăng ký tài khoản; không thu email hoặc mật khẩu.',
                    'Không thu vị trí, danh bạ hoặc dữ liệu microphone.',
                    'Không yêu cầu quyền camera; ảnh chỉ được chọn khi người dùng mở thư viện ảnh.',
                    'Không tích hợp analytics, quảng cáo hoặc telemetry ảnh.',
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  'Điều này không có nghĩa ứng dụng không xử lý dữ liệu: ảnh '
                  'được người dùng chọn vẫn phải gửi qua mạng để inference.',
                ),
              ],
            ),
            SizedBox(height: 14),
            LegalSectionCard(
              title: '3. Cách xử lý ảnh',
              children: [
                LegalBulletList(
                  items: [
                    'Flutter gửi ảnh trực tiếp tới FastAPI đã cấu hình.',
                    'FastAPI xử lý ảnh bằng YOLO26n-seg hoặc YOLO26n-seg + VMamba.',
                    'Mobile nhận metadata kỹ thuật và overlay kết quả.',
                    'Ảnh local và kết quả chỉ được giữ trong state của phiên hiện tại theo implementation mobile.',
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  'Ứng dụng không cam kết thời điểm xóa dữ liệu trên server vì '
                  'chính sách đó phụ thuộc dịch vụ AI và môi trường triển khai.',
                ),
              ],
            ),
            SizedBox(height: 14),
            LegalSectionCard(
              title: '4. Lưu trữ trong mobile',
              children: [
                LegalBulletList(
                  items: [
                    'Không persist ảnh hoặc overlay vào bộ nhớ ứng dụng.',
                    'Không tạo Local History hoặc cloud history.',
                    'Không có user database, profile hoặc đồng bộ với website.',
                    'Không lưu Base64 sau khi đã decode thành bytes cần hiển thị.',
                  ],
                ),
              ],
            ),
            SizedBox(height: 14),
            LegalSectionCard(
              title: '5. Kết nối mạng',
              children: [
                Text(
                  'Debug có thể sử dụng HTTP qua mạng LAN để phục vụ nghiên '
                  'cứu và chỉ phù hợp trên mạng tin cậy. Cấu hình release yêu '
                  'cầu AI_BASE_URL sử dụng HTTPS.',
                ),
              ],
            ),
            SizedBox(height: 14),
            LegalSectionCard(
              title: '6. Chia sẻ và dịch vụ bên thứ ba',
              children: [
                Text(
                  'Ứng dụng mobile không tích hợp quảng cáo, analytics hoặc '
                  'dịch vụ chia sẻ dữ liệu bên thứ ba trong phiên bản hiện tại. '
                  'Ảnh được gửi tới dịch vụ AI do người triển khai cấu hình; '
                  'chính sách vận hành của dịch vụ đó cần được xem xét riêng.',
                ),
              ],
            ),
            SizedBox(height: 14),
            LegalSectionCard(
              title: '7. Quyền kiểm soát của người dùng',
              children: [
                LegalBulletList(
                  items: [
                    'Dùng Đặt lại hoặc chọn ảnh khác để loại ảnh hiện tại khỏi màn hình.',
                    'Đóng ứng dụng để kết thúc state phiên hiện tại.',
                    'Không có hồ sơ cá nhân hoặc lịch sử mobile cần yêu cầu xóa trong phiên bản này.',
                  ],
                ),
              ],
            ),
            SizedBox(height: 14),
            LegalSectionCard(
              title: '8. Thay đổi chính sách',
              children: [
                Text(
                  'Chính sách sẽ được cập nhật nếu kiến trúc hoặc cách xử lý dữ '
                  'liệu thay đổi. Tài khoản, đồng bộ dữ liệu và lịch sử phân '
                  'tích chỉ là khả năng mở rộng tương lai, chưa có trong phiên '
                  'bản hiện tại.',
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
