# Dữ liệu xuất từ MongoDB (`polypweb`)

Xuất ngày 11/11/2026 từ máy chạy thử của nhóm, mỗi dòng là một document (Extended JSON, dạng `mongoimport` đọc được).

| File | Collection | Số document |
|---|---|---|
| `users.json` | `users` | 3 |
| `diagnosis_history.json` | `diagnosis_history` | 20 |
| `video_analysis.json` | `video_analysis` | 2 |

Lưu ý:

- `users.json` đã **bỏ trường `passwordHash`**, nên không đăng nhập được bằng các tài khoản này. Sau khi nhập dữ liệu, hãy đăng ký tài khoản mới ở `/register`.
- Ảnh và video mà các bản ghi trỏ tới (`originalImageUrl`, `resultImageUrl`, `originalVideoFile`, `resultVideoFile`) nằm trong thư mục `storage/` của máy chạy thử, không kèm trong bản nộp; trang lịch sử sẽ thiếu ảnh cho các bản ghi này.
- 7 bản ghi trong `diagnosis_history` có `modelType` là `YOLO26n-seg` hoặc `YOLO26n-VMamba-seg`: đây là lượt chạy thử với mô hình bản nano ở giai đoạn đầu, không thuộc kết quả trong báo cáo. Các bản ghi còn lại dùng hai mô hình của báo cáo (`YOLO26s-seg`, `YOLO26s-TSVM-FP32-seg`).
- Chỉ mục (index) không nằm trong file JSON; website tự tạo khi khởi động, hoặc chạy `khoi_tao_csdl.js` ở thư mục cha.

## Nhập lại dữ liệu

Cần MongoDB Database Tools (`mongoimport`):

```powershell
cd co_so_du_lieu\du_lieu_xuat
mongoimport --uri "mongodb://localhost:27017/polypweb" --collection users --file users.json
mongoimport --uri "mongodb://localhost:27017/polypweb" --collection diagnosis_history --file diagnosis_history.json
mongoimport --uri "mongodb://localhost:27017/polypweb" --collection video_analysis --file video_analysis.json
```

Không bắt buộc nhập dữ liệu này để chạy website: CSDL rỗng vẫn chạy bình thường.
