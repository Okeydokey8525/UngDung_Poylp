# PolypVision Mobile — Direct AI

PolypVision Mobile là ứng dụng Flutter phục vụ nghiên cứu phân đoạn polyp trên ảnh nội soi đại trực tràng. Runtime production kết nối trực tiếp tới FastAPI:

```text
Flutter → FastAPI → AI models
```

Hai AI model hiện tại là `YOLO26n-seg` và `YOLO26n-VMamba-seg`.

Ứng dụng Mobile không cần Spring Boot. **MongoDB không cần** cho Direct AI runtime. Tổng quan toàn dự án: [../README.md](../README.md). Contract AI: [../polypweb/ai-service/README.md](../polypweb/ai-service/README.md).

## 1. Runtime cuối

`main.dart` khởi tạo `ProviderScope(child: PolypVisionApp())`. `PolypVisionApp` dùng Direct AI router và chỉ khởi tạo provider/client cần cho FastAPI.

Source Spring-backed cũ vẫn được giữ trong `LegacyPolypVisionApp` để rollback và regression test, nhưng không được khởi tạo đồng thời với app shell/provider Direct AI.

Mobile runtime không tạo `AuthController`, `AuthRepository`, Spring `ApiClient`, `CookieJar`, CSRF controller và không gọi `GET /api/v1/me` của Spring.

## 2. Tính năng

- Home AI với service health và model readiness.
- Single inference bằng `YOLO26n-seg` hoặc `YOLO26n-VMamba-seg`.
- Comparison hai model trên cùng một ảnh qua một request.
- Chọn ảnh JPG/JPEG/PNG, preview và validate tối đa 10 MB.
- Upload progress, processing state, cancel, retry, reset và lỗi tiếng Việt.
- Metadata: detected, label, confidence, mask count, processing time.
- Ảnh gốc và JPEG overlay Base64 được decode an toàn trong bộ nhớ.
- Fullscreen zoom/pan.
- Responsive phone/tablet, portrait/landscape.
- Chế độ light/dark/system, lưu theme preference.
- About, Privacy, Terms và Research Disclaimer.

Không có account/login, cloud sync, MongoDB, local/cloud history, analytics, chia sẻ hoặc PDF trong Direct AI runtime.

## 3. Screenshot placeholders

<!-- SCREENSHOT: Mobile Home AI -->
<!-- Đề xuất: docs/images/mobile-home.png -->
<!-- ![Mobile Home AI](docs/images/mobile-home.png) -->
<!-- SCREENSHOT: Mobile health/models -->
<!-- Đề xuất: docs/images/mobile-health-models.png -->
<!-- ![Mobile health and models](docs/images/mobile-health-models.png) -->
<!-- SCREENSHOT: Analyze picker -->
<!-- Đề xuất: docs/images/mobile-analyze-picker.png -->
<!-- ![Analyze picker](docs/images/mobile-analyze-picker.png) -->
<!-- SCREENSHOT: Baseline result -->
<!-- Đề xuất: docs/images/mobile-result-baseline.png -->
<!-- ![Baseline result](docs/images/mobile-result-baseline.png) -->
<!-- SCREENSHOT: VMamba result -->
<!-- Đề xuất: docs/images/mobile-result-vmamba.png -->
<!-- ![VMamba result](docs/images/mobile-result-vmamba.png) -->
<!-- SCREENSHOT: Model comparison -->
<!-- Đề xuất: docs/images/mobile-comparison.png -->
<!-- ![Model comparison](docs/images/mobile-comparison.png) -->
<!-- SCREENSHOT: Fullscreen zoom/pan -->
<!-- Đề xuất: docs/images/mobile-fullscreen.png -->
<!-- ![Fullscreen zoom and pan](docs/images/mobile-fullscreen.png) -->
<!-- SCREENSHOT: Dark mode -->
<!-- Đề xuất: docs/images/mobile-dark-mode.png -->
<!-- ![Dark mode](docs/images/mobile-dark-mode.png) -->
<!-- SCREENSHOT: Tablet layout -->
<!-- Đề xuất: docs/images/mobile-tablet.png -->
<!-- ![Tablet layout](docs/images/mobile-tablet.png) -->

Các dòng ảnh đều được comment để README không tạo broken image; chưa tạo `docs/images` trong milestone tài liệu này.

## 4. Công nghệ và yêu cầu

Dependency Direct AI chính trong `pubspec.yaml`:

- Flutter/Dart.
- `flutter_riverpod`.
- `dio`.
- `go_router`.
- `image_picker`.
- `shared_preferences` cho theme preference.

Yêu cầu phát triển:

- Flutter stable tương thích Dart SDK `^3.12.2`.
- Android SDK và Java 17.
- FastAPI cùng hai checkpoint thật.
- Android Emulator hoặc thiết bị Android thật.
- PC/phone cùng mạng nếu dùng IP LAN.

```powershell
flutter doctor
flutter devices
```

Không hardcode device ID hoặc IP LAN vào source.

## 5. FastAPI contract Mobile

| Method | Endpoint | Mục đích |
|---|---|---|
| `GET` | `/api/v1/health` | Health tổng hợp |
| `GET` | `/api/v1/models` | Hai model và readiness |
| `POST` | `/api/v1/inference` | Multipart `image` + `modelKey` |
| `POST` | `/api/v1/comparison` | Multipart `image` |

Model key:

- `YOLO26n-seg`.
- `YOLO26n-VMamba-seg`.

Response inference/comparison chứa JSON metadata và overlay `{mediaType: image/jpeg, encoding: base64, data: ...}`. Mobile decode Base64 thành bytes trước khi render; lỗi JSON được ánh xạ thành thông báo an toàn và request ID hỗ trợ truy vết.

## 6. Cấu hình `AI_BASE_URL`

Ứng dụng đọc compile-time define:

```text
AI_BASE_URL
```

Quy tắc từ source:

- Debug mặc định: `http://10.0.2.2:8000` nếu không truyền giá trị.
- Debug cho phép HTTP để phát triển trên emulator/LAN.
- Release bắt buộc HTTPS.
- Release từ chối localhost, `10.0.2.2`, loopback, link-local, private IPv4 và host `.local`.
- URL không được chứa credentials, query hoặc fragment.
- Không hardcode endpoint production trong source.

## 7. Chuẩn bị FastAPI

Từ repository root:

```powershell
cd ".\polypweb\ai-service"
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000
```

`0.0.0.0` cần khi điện thoại thật truy cập qua LAN. Nếu chỉ Android Emulator/client local, có thể bind `127.0.0.1`. Kiểm tra `/api/v1/health` và `/api/v1/models` trước khi demo.

## 8. Chạy trên Android Emulator

```powershell
cd ".\app_polyp"
flutter pub get
flutter run --dart-define=AI_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` chỉ dành cho Android Emulator để truy cập host. Không dùng cho điện thoại thật.

## 9. Chạy trên thiết bị Android thật

```powershell
cd ".\app_polyp"
flutter devices
flutter run -d <DEVICE_ID_FROM_FLUTTER_DEVICES> `
  --dart-define=AI_BASE_URL=http://<IP-LAN>:8000
```

Điều kiện:

- `<IP-LAN>` là IP của PC chạy FastAPI.
- PC và điện thoại cùng mạng.
- FastAPI bind `0.0.0.0`.
- Firewall cho phép thiết bị truy cập TCP 8000.
- Chỉ mở service trong mạng nghiên cứu tin cậy.

Không đưa IP/device ID thật vào source hoặc tài liệu được commit.

## 10. Android debug HTTP và release HTTPS

Manifest main/release đặt `android:usesCleartextTraffic="false"`. Debug manifest override cleartext thành `true` và dùng network security config dành riêng cho debug để thử HTTP emulator/LAN.

Release phải dùng endpoint HTTPS công khai hợp lệ. Validation trong app từ chối HTTP và host phát triển/private/loopback ở release.

## 11. Kiểm thử Flutter

```powershell
cd ".\app_polyp"
flutter pub get
dart format lib test
flutter analyze
flutter test
```

Kiểm tra whitespace repository:

```powershell
git diff --check
```

Suite bao phủ startup/navigation, cấu hình URL, health/models, image validation, inference, comparison, progress/cancel/retry, JSON parsing, error mapping, responsive/accessibility, legal/privacy/release hardening và legacy wrapper regression.

Tại thời điểm README M8 được cập nhật và xác minh: **498/498 tests PASS** và `flutter analyze` **PASS**. Đây là snapshot tại thời điểm cập nhật README, không phải số lượng test bất biến.

Lưu ý môi trường hiện tại từng có dangling Gradle transform dưới `build/`, khiến `dart format .` có thể lỗi khi duyệt artifact sinh tự động. Lệnh chuẩn cho source là `dart format lib test`; có thể xóa/rebuild artifact bằng quy trình Flutter phù hợp trước khi thử format toàn cây.

## 12. FastAPI và Web regression tests

FastAPI được dùng chung nên chạy suite contract:

```powershell
cd ".\polypweb\ai-service"
.\.venv\Scripts\python.exe -m pytest -q
```

Tại thời điểm README M8 được cập nhật và xác minh: **50/50 tests PASS**.

Spring Boot không cần để chạy Mobile, nhưng legacy FastAPI contract vẫn được Web dùng:

```powershell
cd ".\polypweb"
.\mvnw.cmd test
.\mvnw.cmd clean package
```

Tại thời điểm README M8 được cập nhật và xác minh: **261/261 tests PASS**, clean package **PASS**.

## 13. Build debug APK

```powershell
cd ".\app_polyp"
flutter build apk --debug `
  --dart-define=AI_BASE_URL=http://10.0.2.2:8000
```

Artifact:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

Debug APK chỉ dùng cho phát triển/nghiên cứu.

## 14. Release signing và build

Không commit keystore, `android/key.properties`, password hoặc signing secret. Gradle cố ý chặn release nếu thiếu signing config; không fallback sang debug key.

Chuẩn bị file local từ mẫu:

```powershell
Copy-Item .\android\key.properties.example .\android\key.properties
```

Build khi đã có signing hợp lệ và HTTPS endpoint thật:

```powershell
flutter build apk --release `
  --dart-define=AI_BASE_URL=https://<VALID_PUBLIC_AI_HOST>
```

Tùy nhu cầu:

```powershell
flutter build apk --release --split-per-abi `
  --dart-define=AI_BASE_URL=https://<VALID_PUBLIC_AI_HOST>

flutter build appbundle --release `
  --dart-define=AI_BASE_URL=https://<VALID_PUBLIC_AI_HOST>
```

Không build release với domain placeholder.

## 15. Quyền riêng tư

Direct AI Mobile:

- không tạo account/login;
- không persist ảnh, Base64 hoặc result/history vào database;
- không có Local History hoặc cloud sync;
- không tích hợp analytics/telemetry ảnh;
- không gửi ảnh tới Spring Boot;
- chỉ gửi ảnh tới `AI_BASE_URL` được cấu hình;
- không log image bytes;
- chỉ yêu cầu quyền Android `INTERNET`.

Gallery dùng system image picker. Ứng dụng không yêu cầu camera, vị trí, microphone, danh bạ hoặc quyền storage rộng. Release phải dùng HTTPS.

## 16. Trang pháp lý

Direct router có:

- `/about` — mục tiêu nghiên cứu và hai model.
- `/privacy` — dữ liệu được xử lý và giới hạn lưu trữ.
- `/terms` — phạm vi sử dụng nghiên cứu.
- `/disclaimer` — cảnh báo không thay thế chuyên môn y tế.

Disclaimer chính thức dùng thống nhất:

> “Kết quả chỉ phục vụ nghiên cứu và hỗ trợ tham khảo, không thay thế chẩn đoán hoặc quyết định chuyên môn của bác sĩ.”

## 17. Manual Android validation

Tại thời điểm hoàn tất M1–M7, kiểm thử trên thiết bị Android thật đã thành công cho:

Thiết bị tham chiếu đã được ghi nhận trong tài liệu kiểm thử trước đó là **Samsung Galaxy A51**; cấu hình chạy không hardcode model hoặc device ID của thiết bị này.

- [x] Health.
- [x] Model readiness.
- [x] Baseline inference.
- [x] VMamba inference.
- [x] Model comparison.
- [x] Fullscreen zoom/pan.
- [x] Retry/error.
- [x] Rotate portrait/landscape.
- [x] Dark mode.
- [x] Back navigation.

Checklist trước demo:

- [ ] FastAPI bind `0.0.0.0:8000` trong mạng tin cậy.
- [ ] `/api/v1/health` và `/api/v1/models` báo hai model ready.
- [ ] PC/phone cùng mạng và firewall cho TCP 8000.
- [ ] App chạy với đúng `AI_BASE_URL`.
- [ ] Có ảnh JPG và PNG hợp lệ được phép dùng.
- [ ] Kiểm tra portrait, landscape và dark mode.

## 18. Giới hạn đã biết

- Không có offline inference.
- Không có account/login, Local History, cloud history hoặc cloud sync.
- Hiệu năng phụ thuộc máy chạy model và mạng.
- Base64 làm response lớn hơn raw binary.
- Release cần signing cục bộ và HTTPS endpoint thật.
- Timing quan sát trên thiết bị không phải benchmark khoa học.
- Kết quả một ảnh không chứng minh model nào tốt hơn.
- Không phải thiết bị y tế hoặc hệ thống chẩn đoán.

## 19. Hướng phát triển

- Mobile Account & Cloud Sync.
- Optional Local History.
- Production HTTPS deployment và API protection.
- Process isolation/job worker nếu cần hard cancellation inference.
- Profiling và benchmark có kiểm soát trên tập dữ liệu nghiên cứu.
