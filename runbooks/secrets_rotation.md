# RUNBOOK: HƯỚNG DẪN XOAY VÒNG SECRETS (SECRETS ROTATION RUNBOOK)

Runbook này hướng dẫn cách thay đổi (rotate) mật khẩu cơ sở dữ liệu trên AWS Secrets Manager và kiểm chứng cơ chế đồng bộ tự động của External Secrets Operator (ESO) vào cụm Kubernetes mà không làm gián đoạn ứng dụng (không restart pod).

---

## 1. Kiến trúc luồng xoay vòng (Rotation Flow)
1.  Người vận hành cập nhật mật khẩu mới trên dịch vụ **AWS Secrets Manager**.
2.  **External Secrets Operator (ESO)** đang chạy trong cụm Kubernetes liên tục thăm dò (polling) AWS Secrets Manager mỗi 10 giây (cấu hình bởi `refreshInterval` trong `ExternalSecret`).
3.  Khi phát hiện sự thay đổi, ESO cập nhật trực tiếp nội dung của Kubernetes Secret (`db-secret`) trong namespace `demo`.
4.  Do Kubernetes Secret được gắn vào Pod ứng dụng dưới dạng **Volume** (thư mục `/etc/secrets/`), dịch vụ Kubelet trên Node sẽ tự động cập nhật nội dung file trên đĩa.
5.  Ứng dụng đọc trực tiếp file mật khẩu mới từ đĩa mà **không cần restart Pod** (Zero Downtime).

---

## 2. Quy trình thực hiện cập nhật mật khẩu

### Bước 1: Tạo AWS Credentials trên cụm (Chỉ làm 1 lần)
Chạy lệnh sau trên EC2 để tạo Secret chứa Access Key kết nối AWS:
```bash
kubectl create secret generic aws-creds \
  -n demo \
  --from-literal=access-key="<YOUR_AWS_ACCESS_KEY_ID>" \
  --from-literal=secret-key="<YOUR_AWS_SECRET_ACCESS_KEY>"
```
*Lưu ý*: Không commit file chứa credentials này lên Git.

### Bước 2: Thay đổi mật khẩu trên AWS Secrets Manager
Sử dụng AWS CLI hoặc AWS Console để cập nhật giá trị của secret `demo/db/password` sang một mật khẩu mới:
```bash
aws secretsmanager put-secret-value \
  --secret-id demo/db/password \
  --secret-string "new-secure-password-2026" \
  --region ap-southeast-1
```

---

## 3. Quy trình nghiệm thu & Kiểm tra tự động

### 1. Kiểm tra Kubernetes Secret đã cập nhật chưa
Chạy lệnh sau trên cụm để giải mã Secret cục bộ và kiểm tra xem mật khẩu mới đã được đồng bộ chưa (thời gian đồng bộ `< 60 giây`):
```bash
kubectl get secret db-secret -n demo -o jsonpath='{.data.password}' | base64 -d; echo
```
*Kỳ vọng*: Trả về chuỗi `"new-secure-password-2026"`.

### 2. Kiểm tra tuổi thọ Pod (AGE) xem có bị restart không
Chạy lệnh kiểm tra thời gian hoạt động của các Pod:
```bash
kubectl get pods -n demo -l app=api
```
*Kỳ vọng*: Cột **AGE** không bị reset về 0 (Pod không bị restart). Trạng thái **RESTARTS** bằng `0`.

### 3. Kiểm tra file mật khẩu cập nhật trực tiếp trong Pod
Chạy lệnh đọc trực tiếp file mount mật khẩu bên trong container:
```bash
kubectl exec -it $(kubectl get pods -n demo -l app=api -o jsonpath='{.items[0].metadata.name}') -n demo -- cat /etc/secrets/password
```
*Kỳ vọng*: Trả về chuỗi mật khẩu mới `"new-secure-password-2026"`. Điều này chứng minh Kubelet đã cập nhật file đĩa tự động thành công.
