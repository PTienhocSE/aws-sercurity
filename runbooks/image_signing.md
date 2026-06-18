# RUNBOOK: HƯỚNG DẪN KÝ VÀ XÁC MINH CHỮ KÝ ẢNH (IMAGE SIGNING & VERIFICATION RUNBOOK)

Runbook này hướng dẫn quy trình tạo chữ ký số cho Container Image bằng Cosign, cấu hình Sigstore Policy Controller để chặn các ảnh không hợp lệ, và cách khắc phục sự cố triển khai.

---

## 1. Cơ chế xác minh chữ ký (Image Verification Flow)
1.  **Bước Build & Sign (CI)**: GitHub Actions build Docker image, chạy quét quét Trivy. Nếu sạch lỗ hổng, CI sử dụng công cụ **Cosign** ký lên digest của image bằng khóa Private Key và push chữ ký lên Registry cùng với image.
2.  **Bước Deploy (Kubernetes)**: Khi người dùng khai báo deploy Pod, Sigstore Policy Controller (Admission Webhook) sẽ can thiệp trước khi Pod được tạo.
3.  **Xác minh**: Policy Controller đọc cấu hình `ClusterImagePolicy`, sử dụng khóa Public Key để xác minh chữ ký của image trên Registry.
    *   Nếu chữ ký khớp và hợp lệ -> **Cho phép triển khai (Pass)**.
    *   Nếu image chưa ký hoặc chữ ký không khớp -> **Từ chối (Reject)**.

---

## 2. Quy trình kiểm tra và nghiệm thu

### Kịch bản 1: Triển khai image chưa ký (Unsigned Image)
Thử deploy một image nginx chưa qua ký kết vào namespace đã bật chính sách kiểm tra:
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-unsigned
  namespace: demo
spec:
  containers:
  - name: web
    image: nginx:1.25
    resources: { limits: { cpu: 100m, memory: 64Mi } }
EOF
```
*Kết quả kỳ vọng*: Yêu cầu bị từ chối bởi admission webhook:
`admission webhook "policy.sigstore.dev" denied the request: validation failed: image nginx:1.25 signature verification failed`

### Kịch bản 2: Triển khai image đã được ký hợp lệ
Thay đổi image trong manifest thành image đã được ký thông qua CI:
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-signed
  namespace: demo
spec:
  containers:
  - name: api
    image: ghcr.io/ptienhocse/w10-api:<VERSION_ĐÃ_KÝ>
    resources: { limits: { cpu: 100m, memory: 64Mi } }
EOF
```
*Kết quả kỳ vọng*: Tạo Pod thành công.

---

## 3. Khắc phục sự cố (Troubleshooting)

### Lỗi 1: `no matches for kind ClusterImagePolicy`
*   **Nguyên nhân**: Bạn cố gắng cài đặt cấu hình chính sách hình ảnh trước khi controller `policy-controller` được khởi chạy hoàn toàn.
*   **Cách xử lý**: Đảm bảo ứng dụng `policy-controller` trong ArgoCD đã ở trạng thái `Healthy` và `Synced`. Chạy lệnh nạp lại chính sách thủ công nếu cần:
    ```bash
    kubectl apply -f policies/cluster-image-policy.yaml
    ```

### Lỗi 2: Nhầm lẫn nhãn kích hoạt chính sách trên Namespace
*   **Nguyên nhân**: Sigstore Policy Controller chỉ quét các Namespace có nhãn cấu hình cụ thể.
*   **Cách xử lý**: Kiểm tra xem namespace `demo` đã được gắn nhãn hay chưa:
    ```bash
    kubectl label namespace demo policy.sigstore.dev/include=true --overwrite
    ```
    *Lưu ý*: Chỉ gắn nhãn này **sau khi** ảnh API chính đã được ký và push thành công lên Registry. Nếu gắn nhãn trước khi ký ảnh, ứng dụng chính sẽ bị lock và không thể khởi động.
