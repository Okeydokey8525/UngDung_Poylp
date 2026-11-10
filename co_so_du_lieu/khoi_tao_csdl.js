// Khởi tạo CSDL MongoDB cho website PolypVision (chạy bằng mongosh).
//   mongosh "mongodb://localhost:27017/polypweb" khoi_tao_csdl.js
// Không bắt buộc: Spring Boot tự tạo collection và chỉ mục khi khởi động
// (UserAccountIndexInitializer, DiagnosisHistoryIndexInitializer).
// Script chỉ tạo cấu trúc rỗng, không chứa dữ liệu hay tài khoản nào.

const collections = ["users", "diagnosis_history", "video_analysis"];
const existing = db.getCollectionNames();
for (const name of collections) {
  if (!existing.includes(name)) {
    db.createCollection(name);
    print("Đã tạo collection " + name);
  }
}

db.users.createIndex({ email: 1 }, { unique: true, name: "email" });

db.diagnosis_history.createIndex({ userId: 1, comparisonResult: 1, createdAt: -1 }, { name: "history_user_type_created" });
db.diagnosis_history.createIndex({ userId: 1, comparisonGroupId: 1 }, { name: "history_user_comparison_group" });
db.diagnosis_history.createIndex({ userId: 1, modelType: 1, createdAt: -1 }, { name: "history_user_model_created" });
db.diagnosis_history.createIndex({ userId: 1, detected: 1, createdAt: -1 }, { name: "history_user_detected_created" });

print("Xong. Tài khoản quản trị do AdminSeedRunner tạo từ biến POLYPVISION_ADMIN_EMAIL, POLYPVISION_ADMIN_PASSWORD, POLYPVISION_ADMIN_NAME.");
