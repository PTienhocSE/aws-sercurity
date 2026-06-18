# ARCHITECTURAL DECISION RECORD (ADR): CVE EXCEPTION POLICY

**Mã số**: ADR-003  
**Trạng thái**: Approved  
**Ngày**: 2026-06-18  
**Tác giả**: Platform Security Team

---

## 1. Ngữ cảnh (Context)
Trong quy trình Supply Chain Security (Lab 2.2), chúng ta tích hợp công cụ **Trivy** vào luồng CI (GitHub Actions) để quét lỗ hổng bảo mật. Cấu hình mặc định sẽ dừng (fail) toàn bộ pipeline (`exit-code 1`) nếu phát hiện bất kỳ lỗ hổng bảo mật nào ở mức độ `HIGH` hoặc `CRITICAL`.

Tuy nhiên, trong thực tế vận hành:
*   Có những lỗ hổng bảo mật được phát hiện nhưng nhà cung cấp thư viện hoặc hệ điều hành **chưa phát hành bản vá (no fix available)**.
*   Việc block vĩnh viễn CI/CD pipeline khiến đội ngũ phát triển không thể phát hành các tính năng mới hoặc vá các lỗi khác của ứng dụng, gây ảnh hưởng trực tiếp tới hoạt động kinh doanh.

---

## 2. Quyết định (Decision)
Chúng ta thiết lập một quy trình xử lý ngoại lệ **CVE Exception Policy** có thời hạn, đảm bảo tính liên tục của CI/CD mà vẫn duy trì kiểm soát bảo mật chặt chẽ:

1.  **Sử dụng file ngoại lệ của Trivy (`.trivyignore`)**:
    Các CVE nằm trong danh sách ngoại lệ được chấp thuận sẽ được khai báo trong file `.trivyignore` ở thư mục gốc của mã nguồn để Trivy bỏ qua trong quá trình quét.
2.  **Yêu cầu thời hạn hết hạn (Expiration Date)**:
    Mỗi ngoại lệ CVE phải đi kèm với một comment ghi rõ ngày hết hạn (tối đa 30 ngày). Sau ngày này, CVE phải được đánh giá lại hoặc cập nhật bản vá mới nếu có.
3.  **Quy trình phê duyệt**:
    *   Nhà phát triển (Developer) phải tạo tài liệu phân tích rủi ro (Risk Assessment) giải thích lý do vì sao CVE này không gây nguy hiểm trực tiếp (ví dụ: Thư viện chứa lỗi không được gọi tới trong runtime của ứng dụng).
    *   Tài liệu phân tích phải được ký duyệt bởi Trưởng nhóm Bảo mật (Security Lead) hoặc SRE Team trước khi merge cấu hình `.trivyignore` mới vào nhánh chính (`main`).

---

## 3. Hướng dẫn cấu hình thực tế

Tạo file `.trivyignore` ở thư mục gốc của dự án với định dạng như sau:

```text
# Lỗi CVE-2023-xxxx: Thư viện libssl3 chứa lỗ hổng tràn bộ nhớ nhưng chưa có bản vá từ Ubuntu.
# Đã phân tích: Ứng dụng Flask chỉ dùng HTTP, không bật HTTPS trực tiếp ở container (HTTPS do Ingress đảm nhận).
# Hạn ngoại lệ: Hết hạn vào ngày 2026-07-18 (Sau 30 ngày)
CVE-2023-xxxx
```

Khi chạy quét Trivy trong CI, cấu hình quét sẽ tự động đọc file này để bỏ qua các lỗi đã được phê duyệt, giúp pipeline tiếp tục build và deploy bình thường.
