# PolypVision FastAPI AI Service

FastAPI AI Service là lớp inference dùng chung cho hai client độc lập của PolypVision:

```text
Spring Boot Web ─┐
                 ├─→ FastAPI → YOLO26n-seg / YOLO26n-VMamba-seg
Flutter Mobile ──┘
```

Service tải checkpoint khi khởi động, kiểm tra ảnh, chạy model và trả JSON cùng overlay Base64. Service không quản lý tài khoản, MongoDB, lịch sử hay file ảnh lâu dài.

## 1. Model registry

Registry trong `main.py` có đúng hai model key:

| Model key | Family | Checkpoint mặc định |
|---|---|---|
| `YOLO26n-seg` | `baseline` | `models/yolo26n-seg-best.pt` |
| `YOLO26n-VMamba-seg` | `vmamba` | `models/yolo26n-vmamba-seg-best.pt` |

Checkpoint VMamba cần custom module `custom_ultralytics.vmamba.VMambaBlock` được đăng ký trước khi Ultralytics load file. Source block dùng VSS/SS2D-inspired four-direction selective scan trên YOLO feature maps; checkpoint hiện tại đặt block sau `C2PSA` cuối backbone. Đây không phải tuyên bố rằng model là full Vision Mamba hoặc SegMamba.

Không commit checkpoint hoặc đường dẫn tuyệt đối của máy cá nhân.

## 2. API contract

### 2.1 Legacy API cho Spring Boot

#### `GET /health`

Trả trạng thái service, device và trạng thái load của từng model trong registry. Spring Boot dùng endpoint này cho health/dashboard và kiểm tra hai model trước comparison.

#### `POST /predict`

`multipart/form-data`:

| Field | Kiểu | Nội dung |
|---|---|---|
| `image` | file | JPG/JPEG hoặc PNG |
| `modelType` | string | `YOLO26n-seg` hoặc `YOLO26n-VMamba-seg` |

Phản hồi thành công gồm `success`, `detected`, `label`, `confidence`, `processingTimeMs`, `maskCount`, `modelType`, `originalFileName`, `resultImageBase64` và `message`.

Legacy contract giữ error shape chuẩn của FastAPI để tương thích Spring client hiện tại.

### 2.2 Mobile Direct AI API

#### `GET /api/v1/health`

Trả `requestId`, `status`, `ready`, device công khai, số model ready/tổng model và timestamp. Khi cả hai model unavailable, endpoint trả HTTP 503 kèm JSON mobile contract.

#### `GET /api/v1/models`

Trả danh sách hai model với `key`, `name`, `family` và `ready`.

#### `POST /api/v1/inference`

`multipart/form-data`:

| Field | Kiểu | Nội dung |
|---|---|---|
| `image` | file | JPG/JPEG hoặc PNG |
| `modelKey` | string | Một trong hai model key của registry |

Kết quả gồm thông tin ảnh gốc, metadata model, detected/label/confidence/mask count/processing time, warning nghiên cứu và:

```json
{
  "overlay": {
    "mediaType": "image/jpeg",
    "encoding": "base64",
    "data": "<JPEG_BASE64>"
  }
}
```

#### `POST /api/v1/comparison`

Nhận một field `image`, sau đó chạy Baseline và VMamba trong cùng một comparison request. Phản hồi có `baseline`, `vmamba`, `totalProcessingTimeMs`, kích thước ảnh và `requestId`.

### 2.3 Mobile error envelope

Mọi lỗi thuộc `/api/v1/**` được chuẩn hóa thành JSON, không trả HTML:

```json
{
  "requestId": "...",
  "status": 422,
  "code": "INVALID_IMAGE",
  "message": "Tệp tải lên không phải ảnh hợp lệ.",
  "fieldErrors": {
    "image": "Không thể giải mã nội dung ảnh."
  }
}
```

Client có thể gửi `X-Request-ID` hợp lệ; nếu thiếu hoặc sai định dạng, service tạo UUID mới. Response mobile luôn gắn `X-Request-ID` và body chứa `requestId`.

## 3. Validation ảnh

Các rule hiện tại:

- MIME cho phép: `image/jpeg`, `image/png`.
- Nội dung giải mã phải thật sự là JPEG hoặc PNG và khớp MIME khai báo.
- Dung lượng tối đa: **10 MB**.
- Kích thước ảnh sau decode: tối đa **40.000.000 pixel**.
- File rỗng, file giả ảnh, ảnh hỏng và format không hỗ trợ bị từ chối.
- Tên file được chuẩn hóa trước khi đưa vào response/logical metadata.
- Overlay được `Results.plot()` tạo, chuyển RGB và encode thành **JPEG Base64** không có data-URI prefix.

Service không chỉ tin vào extension hoặc `Content-Type` do client gửi.

## 4. Concurrency và timeout

- Mỗi model runtime có một `asyncio.Lock` để tránh chồng inference trên cùng model.
- Mobile inference/comparison còn đi qua một semaphore toàn cục; mặc định chỉ một request inference được vào vùng xử lý.
- Comparison giữ semaphore cho cả hai lượt Baseline và VMamba để không bị xen ngang bởi mobile inference khác.
- Queue timeout mặc định là 5 giây; hết thời gian trả `SERVICE_BUSY` (503).
- Inference timeout mobile mặc định là 120 giây; hết ngưỡng trả `TIMEOUT` (504) sau khi bảo đảm worker kết thúc.

Giới hạn quan trọng: PyTorch/GPU worker chạy trong thread không thể bị hard-cancel an toàn. Khi chạm timeout, service vẫn giữ lock/semaphore cho đến khi worker kết thúc để tránh chạy chồng. Nếu cần hard cancellation thực sự, hướng phát triển phù hợp là process isolation hoặc job worker.

## 5. Biến môi trường

| Biến | Mặc định | Mô tả |
|---|---|---|
| `AI_BASELINE_MODEL_PATH` | `models/yolo26n-seg-best.pt` | Checkpoint Baseline |
| `AI_MODEL_PATH` | như checkpoint Baseline mặc định | Fallback legacy cho Baseline |
| `AI_VMAMBA_MODEL_PATH` | `models/yolo26n-vmamba-seg-best.pt` | Checkpoint VMamba |
| `AI_DEVICE` | `auto` | `auto`, `cpu`, `cuda:0`, ... |
| `AI_CONFIDENCE_THRESHOLD` | `0.25` | Threshold truyền vào inference |
| `AI_IMAGE_SIZE` | `640` | Image size truyền vào inference |
| `AI_MAX_CONCURRENT_INFERENCE` | `1` | Số mobile inference/comparison đồng thời |
| `AI_INFERENCE_QUEUE_TIMEOUT_SECONDS` | `5.0` | Thời gian chờ semaphore mobile |
| `AI_INFERENCE_TIMEOUT_SECONDS` | `120.0` | Timeout worker mobile |

Giá trị concurrency/timeout không hợp lệ được thay bằng default an toàn. Nếu yêu cầu CUDA nhưng CUDA unavailable, model load báo lỗi thay vì âm thầm đổi device.

## 6. Yêu cầu và cài đặt

- Python tương thích các phiên bản khóa trong `requirements.txt`.
- Hai checkpoint hợp lệ.
- Custom VMamba module đi cùng source.
- GPU tùy chọn; CPU vẫn hoạt động nhưng có thể chậm.

PowerShell:

```powershell
cd ".\polypweb\ai-service"
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

Dependency runtime thực tế gồm FastAPI, Uvicorn, python-multipart, NumPy, Pillow, OpenCV, PyTorch, TorchVision và Ultralytics.

## 7. Chạy service

Chỉ dùng trên máy local:

```powershell
.\.venv\Scripts\python.exe -m uvicorn main:app --host 127.0.0.1 --port 8000
```

Cho Android thật truy cập qua LAN:

```powershell
.\.venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000
```

`0.0.0.0` làm service lắng nghe trên các interface mạng. Chỉ mở firewall trong mạng nghiên cứu tin cậy. Service hiện không tự cung cấp authentication/rate limiting/TLS; không public trực tiếp ra Internet nếu chưa đặt sau lớp HTTPS/API protection phù hợp.

## 8. Kiểm tra thủ công

### Health và models

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
Invoke-RestMethod http://127.0.0.1:8000/api/v1/health
Invoke-RestMethod http://127.0.0.1:8000/api/v1/models
```

### Legacy prediction

Với `curl.exe` trên Windows:

```powershell
curl.exe -X POST "http://127.0.0.1:8000/predict" `
  -F "image=@C:\path\to\sample.jpg;type=image/jpeg" `
  -F "modelType=YOLO26n-seg"
```

### Mobile inference

```powershell
curl.exe -X POST "http://127.0.0.1:8000/api/v1/inference" `
  -H "X-Request-ID: manual-inference-001" `
  -F "image=@C:\path\to\sample.png;type=image/png" `
  -F "modelKey=YOLO26n-VMamba-seg"
```

### Mobile comparison

```powershell
curl.exe -X POST "http://127.0.0.1:8000/api/v1/comparison" `
  -H "X-Request-ID: manual-comparison-001" `
  -F "image=@C:\path\to\sample.jpg;type=image/jpeg"
```

Không dùng ảnh bệnh nhân thật ngoài quy trình dữ liệu đã được cho phép.

## 9. Automated tests

Cài dependency test và chạy:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest -q
```

Suite bao phủ legacy compatibility, mobile health/models, inference, comparison, validation ảnh, JPEG overlay, request ID, JSON error envelope, semaphore, lock, queue timeout và inference timeout.

Tại thời điểm README M8 được cập nhật và xác minh: **50/50 tests PASS**. Số này chỉ là trạng thái tại thời điểm tài liệu được cập nhật; luôn chạy lại test sau khi sửa source/dependency.

## 10. Bảo mật và quyền riêng tư

- Service không có account/session và không lưu ảnh/history vào database.
- Ảnh và overlay tồn tại trong bộ nhớ trong thời gian xử lý/response.
- Không log image bytes hoặc Base64 payload.
- Checkpoint path/error chi tiết không được đưa vào mobile public response.
- Request ID hỗ trợ truy vết mà không thay thế authentication.
- Production cần HTTPS, access control, rate limiting/reverse proxy và logging policy phù hợp.
- Không commit `.venv`, checkpoint, cache, log hoặc secret.

## 11. Cấu trúc thư mục

```text
ai-service/
├── custom_ultralytics/
│   └── vmamba.py
├── models/                 # checkpoint local, ignored
├── tests/
├── .gitignore
├── main.py                 # app, legacy routes, model lifecycle
├── mobile_contract.py      # Pydantic response/error schema
├── mobile_routes.py        # /api/v1 Direct AI routes
├── requirements.txt
├── requirements-dev.txt
└── README.md
```

## 12. Giới hạn đã biết

- Chưa có authentication/rate limiting tích hợp trực tiếp trong FastAPI.
- Chưa có process isolation/job queue cho hard cancellation.
- Base64 làm response lớn hơn raw binary; contract hiện giữ định dạng này để tương thích client.
- Hiệu năng phụ thuộc device, model, ảnh và concurrency; timing trong response không tự động là benchmark khoa học.
- Service phục vụ nghiên cứu, không phải API chẩn đoán y tế.

> “Kết quả chỉ phục vụ nghiên cứu và hỗ trợ tham khảo, không thay thế chẩn đoán hoặc quyết định chuyên môn của bác sĩ.”
