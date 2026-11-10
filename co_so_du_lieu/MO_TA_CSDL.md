# Cơ sở dữ liệu của website PolypVision

- Hệ quản trị: **MongoDB** (đã dùng bản Community chạy cục bộ).
- Tên CSDL mặc định: `polypweb`. URI mặc định của profile `dev`: `mongodb://localhost:27017/polypweb`. Đổi bằng biến `POLYPVISION_MONGODB_URI`.
- Chỉ website (Spring Boot) dùng CSDL. Dịch vụ AI (FastAPI) không lưu dữ liệu.

## Không cần nhập dữ liệu trước

Nhóm **không đính kèm bản sao dữ liệu**, vì CSDL đang dùng chỉ chứa tài khoản, ảnh và lịch sử chẩn đoán của người thử nghiệm.

Khi Spring Boot khởi động lần đầu với một CSDL rỗng:
1. Spring Data MongoDB tự tạo ba collection bên dưới khi có bản ghi đầu tiên.
2. `UserAccountIndexInitializer` và `DiagnosisHistoryIndexInitializer` tự tạo chỉ mục.
3. `AdminSeedRunner` tạo tài khoản quản trị nếu đặt ba biến `POLYPVISION_ADMIN_EMAIL`, `POLYPVISION_ADMIN_PASSWORD`, `POLYPVISION_ADMIN_NAME`. Mật khẩu chỉ lưu dạng băm (BCrypt).
4. Tài khoản người dùng thường đăng ký trên trang `/register`.

Nếu muốn tạo sẵn cấu trúc CSDL (ba collection và các chỉ mục, không có dữ liệu) trước khi chạy website, dùng script đi kèm:

```bash
mongosh "mongodb://localhost:27017/polypweb" khoi_tao_csdl.js
```

Ảnh và video tải lên không nằm trong MongoDB. Chúng được ghi ra thư mục `storage/` (đổi bằng biến `POLYPVISION_STORAGE_ROOT`). MongoDB chỉ lưu đường dẫn tới các file đó.

## Các collection

### `users` (`document/UserAccount.java`)

| Trường | Kiểu | Ghi chú |
|---|---|---|
| `_id` | String | |
| `fullName` | String | |
| `email` | String | chỉ mục duy nhất |
| `passwordHash` | String | BCrypt |
| `role` | `USER` / `ADMIN` | |
| `enabled` | boolean | |
| `createdAt`, `updatedAt` | LocalDateTime | |

### `diagnosis_history` (`document/DiagnosisHistory.java`)

Mỗi bản ghi là một lần phân đoạn ảnh. Khi so sánh hai mô hình, hệ thống ghi hai bản ghi có chung `comparisonGroupId`.

| Trường | Kiểu | Ghi chú |
|---|---|---|
| `_id`, `userId` | String | |
| `fileName`, `modelType` | String | `modelType`: `YOLO26s-seg` hoặc `YOLO26s-TSVM-FP32-seg` |
| `detected`, `label`, `confidence`, `maskCount` | | kết quả phân đoạn |
| `processingTimeMs`, `aiRoundTripMs` | double | thời gian suy luận, thời gian khứ hồi |
| `imageWidth`, `imageHeight` | Integer | |
| `originalImageUrl`, `resultImageUrl` | String | đường dẫn trong `storage/` |
| `comparisonGroupId`, `comparisonResult` | String, boolean | gom cặp khi so sánh |
| `groundTruthMetrics` | object | Dice, IoU, Precision, Recall và số pixel TP/FP/FN, chỉ có khi ảnh thuộc tập val có nhãn |
| `createdAt` | LocalDateTime | |

Chỉ mục: `history_user_type_created` (userId, comparisonResult, createdAt↓), `history_user_comparison_group` (userId, comparisonGroupId), `history_user_model_created` (userId, modelType, createdAt↓), `history_user_detected_created` (userId, detected, createdAt↓).

### `video_analysis` (`document/VideoAnalysis.java`)

Mỗi bản ghi là một lần phân tích video.

| Nhóm trường | Trường |
|---|---|
| Định danh | `_id`, `userId`, `fileName`, `modelType`, `createdAt` |
| Tốc độ lấy mẫu | `sampleFps`, `requestedSampleFps`, `sampleRateReduced`, `outputFps`, `framesHeld` |
| Video gốc | `sourceFps`, `sourceFrameCount`, `durationSec`, `width`, `height`, `originalSizeBytes` |
| Kết quả | `framesProcessed`, `framesWithPolyp`, `maxConfidence` |
| Thời gian | `processingTimeMs`, `averageInferenceMs`, `throughputFps`, `aiRoundTripMs` |
| File | `originalVideoFile`, `resultVideoFile` (trong `storage/`) |
