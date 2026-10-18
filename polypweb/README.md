# PolypVision Web — Spring Boot

Module Web cung cấp giao diện Thymeleaf, tài khoản, lịch sử và quản trị cho PolypVision. Spring Boot là client của FastAPI qua legacy contract; Flutter Mobile Direct AI không đi qua module này.

```text
Browser → Spring Boot → FastAPI → AI Models
              │
              ├→ MongoDB
              └→ Local Image Storage
```

Tài liệu FastAPI: [ai-service/README.md](ai-service/README.md). Tổng quan toàn repository: [../README.md](../README.md).

## 1. Tính năng

- Đăng ký, đăng nhập, đăng xuất; vai trò `USER` và `ADMIN`.
- Dashboard người dùng và dashboard quản trị.
- Phân tích ảnh bằng `YOLO26s-seg` hoặc `YOLO26s-TSVM-FP32-seg`.
- So sánh hai model trên cùng một ảnh.
- Lưu ảnh gốc, overlay và metadata để xem lại sau restart.
- Lịch sử phân tích và lịch sử so sánh; tìm kiếm, lọc, phân trang, xóa.
- Hồ sơ, đổi mật khẩu, khóa/mở khóa tài khoản và đổi vai trò.
- Tải ảnh và xuất metadata theo ownership.
- Health/Actuator, request ID và các trang Privacy/Terms/Disclaimer.

Dashboard và processing time mô tả hoạt động hệ thống; chúng không phải mAP, Dice, IoU hoặc benchmark khoa học.

## 2. Công nghệ

- Java 17.
- Spring Boot 4.1, Spring MVC, Spring Security, Spring Data MongoDB, Validation và Actuator.
- Thymeleaf, Bootstrap 5, Bootstrap Icons, CSS và JavaScript.
- Maven Wrapper.
- MongoDB.
- Java HTTP client adapter gọi FastAPI.

## 3. Cấu trúc module

```text
polypweb/
├── ai-service/                 # FastAPI dùng chung
├── src/
│   ├── main/
│   │   ├── java/com/polyp/polypweb/
│   │   │   ├── api/            # REST API Spring-backed/legacy mobile
│   │   │   ├── client/         # adapter Spring → FastAPI
│   │   │   ├── config/
│   │   │   ├── controller/
│   │   │   ├── document/
│   │   │   ├── repository/
│   │   │   ├── security/
│   │   │   └── service/
│   │   └── resources/
│   │       ├── templates/
│   │       ├── static/
│   │       ├── application.properties
│   │       ├── application-dev.properties
│   │       └── application-prod.properties
│   └── test/
├── storage/                    # runtime, ignored
├── pom.xml
├── mvnw
├── mvnw.cmd
└── README.md
```

## 4. Yêu cầu

- Java 17.
- MongoDB đang chạy hoặc MongoDB URI hợp lệ.
- FastAPI đang chạy với hai model cần dùng ở trạng thái ready.
- Hai checkpoint AI được cấu hình trong `ai-service`; checkpoint không nằm trong Git.
- Quyền ghi vào thư mục storage.
- Maven Wrapper đã có sẵn, không bắt buộc cài Maven toàn cục.

## 5. MongoDB

Profile `dev` mặc định kết nối:

```text
mongodb://localhost:27017/polypweb
```

Các collection chính:

- `users`: tài khoản, password hash, role và trạng thái enabled.
- `diagnosis_history`: metadata phân tích đơn và các record thuộc comparison group.

Spring Data MongoDB tạo document khi ứng dụng hoạt động; các initializer tạo unique/index cần thiết. Không cần tạo collection thủ công. Metadata lưu đường dẫn tương đối tới file ảnh, không lưu Base64 overlay dài.

Có thể override URI:

```powershell
$env:POLYPVISION_MONGODB_URI="mongodb://localhost:27017/polypweb"
```

## 6. Phụ thuộc FastAPI

Spring Boot gọi đúng legacy contract:

| Method | Endpoint | Dùng cho |
|---|---|---|
| `GET` | `/health` | dashboard, health và model readiness |
| `POST` | `/predict` | multipart `image` + `modelType` |

`AiInferenceClient` xác minh HTTP status, JSON, `success`, model type và overlay Base64. Nếu FastAPI lỗi hoặc trả sai model, service không tạo lịch sử inference thành công giả.

Model type hợp lệ:

- `YOLO26s-seg`.
- `YOLO26s-TSVM-FP32-seg`.

Chạy FastAPI local:

```powershell
cd ".\ai-service"
.\.venv\Scripts\python.exe -m uvicorn main:app --host 127.0.0.1 --port 8000
```

Chi tiết cài đặt, model registry và contract: [FastAPI README](ai-service/README.md).

## 7. Profile development và production

### `dev`

- Là profile mặc định khi không đặt `SPRING_PROFILES_ACTIVE`.
- Có localhost fallback cho MongoDB và FastAPI.
- Thymeleaf cache tắt, DevTools restart/livereload bật.
- Session cookie chưa bắt buộc Secure để chạy HTTP local.
- Logging của package ứng dụng ở mức DEBUG.

### `prod`

- `POLYPVISION_MONGODB_URI` và `POLYPVISION_AI_BASE_URL` phải được cung cấp.
- Không có localhost fallback cho hai dependency này.
- Thymeleaf cache bật, DevTools tắt.
- Session cookie Secure và HSTS bật; phải triển khai qua HTTPS.
- Logging ứng dụng/Spring ở mức INFO.

Chọn profile:

```powershell
$env:SPRING_PROFILES_ACTIVE="dev"
```

## 8. Biến môi trường

| Biến | Dev | Prod | Mô tả |
|---|---|---|---|
| `SPRING_PROFILES_ACTIVE` | mặc định `dev` | đặt `prod` | Chọn profile |
| `POLYPVISION_MONGODB_URI` | mặc định localhost | bắt buộc | MongoDB URI |
| `POLYPVISION_AI_BASE_URL` | mặc định `http://localhost:8000` | bắt buộc | FastAPI base URL |
| `POLYPVISION_STORAGE_ROOT` | mặc định `storage` | tùy môi trường | Storage root |
| `POLYPVISION_AI_CONNECT_TIMEOUT` | `3s` | `3s` | Connect timeout |
| `POLYPVISION_AI_READ_TIMEOUT` | `15s` | `15s` | Prediction read timeout |
| `POLYPVISION_AI_HEALTH_TIMEOUT` | `2s` | `2s` | Health timeout |
| `POLYPVISION_ADMIN_EMAIL` | tùy chọn | tùy chọn | Email seed admin |
| `POLYPVISION_ADMIN_PASSWORD` | tùy chọn | tùy chọn | Password seed admin |
| `POLYPVISION_ADMIN_NAME` | tùy chọn | tùy chọn | Tên seed admin |

Ba biến admin phải được cung cấp cùng nhau. Không đặt password trong source, `application*.properties` hoặc README.

Ví dụ seed admin local:

```powershell
$env:POLYPVISION_ADMIN_EMAIL="admin@example.com"
$env:POLYPVISION_ADMIN_PASSWORD="<mật khẩu do người dùng tự đặt>"
$env:POLYPVISION_ADMIN_NAME="Administrator"
```

Sau khi seed:

```powershell
Remove-Item Env:POLYPVISION_ADMIN_PASSWORD
```

## 9. Chạy development

Khởi động MongoDB và FastAPI trước. Sau đó từ thư mục `polypweb`:

```powershell
$env:SPRING_PROFILES_ACTIVE="dev"
.\mvnw.cmd spring-boot:run
```

Mở:

- Website: `http://localhost:8080`.
- Spring health: `http://localhost:8080/actuator/health`.
- FastAPI health: `http://127.0.0.1:8000/health`.

Nếu FastAPI tắt, các trang không cần inference vẫn có thể hoạt động khi MongoDB sẵn sàng; diagnosis/comparison sẽ thất bại có kiểm soát.

## 10. Route chính

### Public

| Route | Chức năng |
|---|---|
| `/` | Trang chủ |
| `/about` | Giới thiệu nghiên cứu |
| `/login` | Đăng nhập |
| `/register` | Đăng ký |
| `/privacy`, `/terms`, `/disclaimer` | Trang pháp lý |
| `/actuator/health`, `/actuator/info` | Health/info công khai có giới hạn |

### Yêu cầu đăng nhập

| Route | Chức năng |
|---|---|
| `/dashboard` | Dashboard |
| `/diagnose`, `/diagnoses/{id}` | Phân tích và chi tiết |
| `/compare` | Tạo comparison |
| `/comparisons`, `/comparisons/{id}` | Lịch sử/chi tiết comparison |
| `/history` | Lịch sử phân tích đơn |
| `/profile`, `/profile/change-password` | Hồ sơ và password |

### ADMIN

- `/admin`.
- `/admin/dashboard`.
- `/admin/users` và các thao tác role/enabled.

Các route media/download/export kiểm tra authentication và ownership trước khi trả ảnh/metadata.

## 11. Storage

```text
storage/
├── original/
└── results/
```

- File vật lý dùng UUID, không dùng trực tiếp tên upload.
- Storage nằm ngoài `static`; không có public directory traversal.
- Browser/API nhận ảnh qua controller có authorization và ownership.
- Ảnh gốc giữ định dạng JPEG/PNG hợp lệ; overlay FastAPI được lưu thành JPEG.
- MongoDB lưu metadata và URL tương đối.
- Xóa lịch sử xử lý document và file liên quan.
- Inference thất bại dọn file đã tạo dở và không lưu record thành công giả.
- Backup MongoDB và storage cùng thời điểm để tránh lệch metadata/file.

Giới hạn upload Web hiện là 10 MB; kết quả decode để lưu tối đa 15 MB.

## 12. Security

Source hiện có:

- BCrypt password hashing.
- Spring Security session authentication và session fixation protection.
- CSRF cho Web và REST API Spring-backed.
- Role `USER`/`ADMIN`.
- Ownership theo MongoDB user ID.
- Session timeout 30 phút; cookie `HttpOnly`, `SameSite=Lax`; `Secure` ở profile prod.
- HSTS ở prod.
- Content Security Policy, Referrer Policy, Permissions Policy, frame protection và MIME sniffing protection.
- API error trả JSON, không redirect HTML cho `/api/v1/**`.
- Request correlation ID và logging không chủ động ghi password/Base64/checkpoint path.
- Actuator chỉ expose `health` và `info`; component detail yêu cầu ADMIN.

Đây là hardening của phiên bản hiện tại, không phải chứng nhận bảo mật. Production vẫn cần HTTPS, reverse proxy, secret management, backup và kiểm soát truy cập hạ tầng.

## 13. Spring REST API được giữ cho legacy/regression

Module có `/api/v1/**` cho auth, dashboard, profile, diagnosis và comparison theo session/CSRF. API này thuộc Spring-backed flow cũ và vẫn được test hồi quy. Flutter production hiện dùng Direct AI router và **không** khởi tạo client/session/CSRF của Spring.

Không nhầm Spring `/api/v1/**` với FastAPI `/api/v1/**`: chúng là contract trên hai service/base URL khác nhau.

## 14. Test và package

Chạy test:

```powershell
.\mvnw.cmd test
```

Clean package:

```powershell
.\mvnw.cmd clean package
```

Tại thời điểm README M8 được cập nhật và xác minh: **261/261 tests PASS** và Maven clean package **PASS**. Số lượng là snapshot tại thời điểm tài liệu được cập nhật; chạy lại sau mọi thay đổi.

Suite bao phủ controller/service, validation, MongoDB adapter mock, authentication, session, CSRF, ownership, diagnosis/comparison, image response, history, admin, profile, Actuator và error handling.

## 15. Chạy production

```powershell
$env:SPRING_PROFILES_ACTIVE="prod"
$env:POLYPVISION_MONGODB_URI="<MongoDB URI production>"
$env:POLYPVISION_AI_BASE_URL="https://<FASTAPI_HOST>"
$env:POLYPVISION_STORAGE_ROOT="<thư mục storage bền vững>"

java -jar .\target\polypweb-0.0.1-SNAPSHOT.jar
```

Yêu cầu:

- HTTPS end-to-end hoặc termination đúng cách tại reverse proxy.
- FastAPI và MongoDB không public ngoài phạm vi cần thiết.
- User chạy Java có quyền ghi storage.
- Upload limit của reverse proxy tương thích 10 MB.
- Secret do hệ thống triển khai quản lý, không nằm trong Git.
- Backup MongoDB và file storage đồng bộ.

## 16. Dữ liệu và quyền riêng tư

Web lưu tài khoản, ảnh gốc, overlay, metadata và lịch sử theo chức năng đã mô tả. Người dùng được giới hạn vào dữ liệu thuộc tài khoản; ADMIN có chức năng quản trị được phân quyền. Không sử dụng ảnh để huấn luyện lại nếu chưa có quy trình đồng ý và quản trị dữ liệu phù hợp.

> “Kết quả chỉ phục vụ nghiên cứu và hỗ trợ tham khảo, không thay thế chẩn đoán hoặc quyết định chuyên môn của bác sĩ.”

## 17. Giới hạn đã biết

- Local file storage; chưa có object storage mặc định.
- Chưa có deployment cloud/Docker/Kubernetes trong module.
- Chưa có OAuth, MFA, email verification hoặc reset password qua email.
- Chưa có rate limiting hoàn chỉnh.
- CSP còn cho phép `unsafe-inline` để tương thích theme/chart hiện tại.
- Chưa hỗ trợ video.
- Timing quan sát qua Web không phải benchmark nghiên cứu chuẩn hóa.
- Không phải thiết bị y tế hoặc hệ thống chẩn đoán lâm sàng.

## 18. Không commit

- `target/`, log và artifact tạm.
- `storage/`, ảnh nội soi và database dump chứa dữ liệu thật.
- `.venv`, `__pycache__`, pytest cache.
- Checkpoint `.pt`.
- Password, credential, `.env` hoặc secret.
- Keystore/signing file của Mobile.
