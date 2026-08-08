import 'package:app_polyp/core/network/ai_api_exception.dart';

String aiUserErrorMessage(AiApiException error) {
  if (error.kind == AiFailureKind.cancelled) return 'Yêu cầu đã được hủy.';
  if (error.kind == AiFailureKind.timeout) {
    return 'Quá thời gian xử lý, vui lòng thử lại.';
  }
  if (error.kind == AiFailureKind.connection) {
    return 'Không thể kết nối dịch vụ AI.';
  }
  if (error.kind == AiFailureKind.invalidResponse) {
    return 'Dịch vụ AI trả về phản hồi không hợp lệ.';
  }
  return switch (error.code) {
    'INVALID_IMAGE' => 'Tệp ảnh không hợp lệ.',
    'FILE_TOO_LARGE' => 'Ảnh vượt quá dung lượng 10 MB.',
    'UNSUPPORTED_MEDIA_TYPE' => 'Chỉ hỗ trợ ảnh JPG, JPEG hoặc PNG.',
    'MODEL_NOT_FOUND' => 'Không tìm thấy mô hình đã chọn.',
    'MODEL_NOT_READY' => 'Mô hình hiện chưa sẵn sàng.',
    'SERVICE_BUSY' => 'Dịch vụ AI đang bận, vui lòng thử lại.',
    'TIMEOUT' => 'Quá thời gian xử lý, vui lòng thử lại.',
    'INFERENCE_FAILED' => 'Không thể hoàn tất quá trình phân tích.',
    'INTERNAL_ERROR' => 'Dịch vụ AI gặp lỗi nội bộ.',
    _ => 'Dịch vụ AI trả về phản hồi không hợp lệ.',
  };
}
