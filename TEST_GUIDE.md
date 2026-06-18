# HƯỚNG DẪN KIỂM THỬ LAB 1 & LAB 2 (TEST GUIDE)

Tài liệu này hướng dẫn chi tiết cách chạy lệnh kiểm thử (nghiệm thu) cho từng phần của **Lab 1 (RBAC + Gatekeeper)** và **Lab 2 (Secrets + Supply Chain)** trực tiếp trên cụm Kubernetes của máy chủ EC2.

---

## 1. Thông tin kết nối môi trường Lab
*   **IP công cộng máy chủ EC2**: `18.141.231.240`
*   **Lệnh SSH kết nối nhanh**:
    ```bash
    ssh -i "terraform/security-lab-key.pem" ubuntu@18.141.231.240
    ```

---

## 2. Kiểm thử Lab 1.1 · RBAC (Phân quyền 3 vai trò)

Sau khi SSH vào máy chủ EC2, sao chép và thực thi 4 lệnh dưới đây. Kết quả trả về phải khớp chính xác với cột kỳ vọng:

| # | Lệnh kiểm thử (Copy-paste chạy trên EC2) | Kết quả kỳ vọng | Ý nghĩa |
|---|------------------------------------------|-----------------|---------|
| 1 | `kubectl auth can-i create deploy -n demo --as alice` | **yes** | Alice (developer) được tạo deploy trong ns demo |
| 2 | `kubectl auth can-i create deploy -n kube-system --as alice` | **no** | Alice bị cấm tạo deploy trong ns kube-system |
| 3 | `kubectl auth can-i get pods -A --as bob` | **yes** | Bob (sre) được xem danh sách pods toàn cụm |
| 4 | `kubectl auth can-i delete nodes --as carol` | **no** | Carol (viewer) bị cấm xóa node hệ thống |

---

## 3. Kiểm thử Lab 1.2 · Gatekeeper (4 luật chặn Admission)

Để kiểm duyệt khả năng chặn lọc của OPA Gatekeeper, hãy chạy các kịch bản thử nghiệm deploy manifest xấu dưới đây trong namespace `demo`:

### Kịch bản 1: Thử deploy Pod dùng image `:latest`
*   **Lệnh thực thi**:
    ```bash
    cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: Pod
    metadata:
      name: test-tag-latest
      namespace: demo
    spec:
      containers:
      - name: web
        image: nginx:latest
        resources: { limits: { cpu: 100m, memory: 64Mi } }
    EOF
    ```
*   **Kết quả kỳ vọng**: Bị **Reject** với thông báo:
    `[block-latest-tag] container <web> has disallowed image tag <latest>`

### Kịch bản 2: Thử deploy Pod thiếu resources.limits
*   **Lệnh thực thi**:
    ```bash
    cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: Pod
    metadata:
      name: test-no-limits
      namespace: demo
    spec:
      containers:
      - name: web
        image: nginx:1.25
    EOF
    ```
*   **Kết quả kỳ vọng**: Bị **Reject** với thông báo:
    `[require-resource-limits] container <web> does not have resource limit <cpu>`

### Kịch bản 3: Thử deploy Pod chạy quyền Root (`runAsUser: 0`)
*   **Lệnh thực thi**:
    ```bash
    cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: Pod
    metadata:
      name: test-run-root
      namespace: demo
    spec:
      securityContext:
        runAsUser: 0
      containers:
      - name: web
        image: nginx:1.25
        resources: { limits: { cpu: 100m, memory: 64Mi } }
    EOF
    ```
*   **Kết quả kỳ vọng**: Bị **Reject** với thông báo:
    `[block-root-user] Pod securityContext runAsUser is set to 0 (root)`

### Kịch bản 4: Thử deploy Pod bật `hostNetwork: true`
*   **Lệnh thực thi**:
    ```bash
    cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: Pod
    metadata:
      name: test-host-network
      namespace: demo
    spec:
      hostNetwork: true
      containers:
      - name: web
        image: nginx:1.25
        resources: { limits: { cpu: 100m, memory: 64Mi } }
    EOF
    ```
*   **Kết quả kỳ vọng**: Bị **Reject** với thông báo:
    `[block-host-network] Sharing the host network namespace is not allowed (hostNetwork: true)`

### Kịch bản 5: Thử deploy Pod hợp lệ (PASS)
*   **Lệnh thực thi**:
    ```bash
    cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: Pod
    metadata:
      name: test-valid-pod
      namespace: demo
    spec:
      containers:
      - name: web
        image: nginx:1.25
        resources: { limits: { cpu: 100m, memory: 64Mi } }
    EOF
    ```
*   **Kết quả kỳ vọng**: **Pass** (tạo thành công pod).
*   **Dọn dẹp**: `kubectl delete pod test-valid-pod -n demo`

---

## 4. Kiểm thử Lab 1.3 · Custom Policy (Giới hạn Replicas <= 5)

### Kịch bản A: Thử deploy Deployment có 6 replicas (Lỗi vi phạm)
*   **Lệnh thực thi**:
    ```bash
    cat <<EOF | kubectl apply -f -
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: test-replicas-6
      namespace: demo
    spec:
      replicas: 6
      selector: { matchLabels: { app: web } }
      template:
        metadata: { labels: { app: web } }
        spec:
          containers:
          - name: web
            image: nginx:1.25
            resources: { limits: { cpu: 100m, memory: 64Mi } }
    EOF
    ```
*   **Kết quả kỳ vọng**: Bị **Reject** với thông báo:
    `[limit-max-replicas] Workload replicas count 6 exceeds the maximum allowed replica count of 5`

---

## 5. Kiểm thử Lab 2.1 · ESO Secrets Rotation (Xoay vòng mật khẩu không downtime)

### Bước 1: Tạo Credentials AWS thủ công trên K8s (Không commit Git)
Chạy lệnh này trên EC2 để tạo Secret kết nối AWS Secrets Manager:
```bash
kubectl create secret generic aws-creds \
  -n demo \
  --from-literal=access-key="<YOUR_AWS_ACCESS_KEY_ID>" \
  --from-literal=secret-key="<YOUR_AWS_SECRET_ACCESS_KEY>"
```

### Bước 2: Đổi giá trị trên AWS Secrets Manager
Đổi giá trị của secret `demo/db/password` trên AWS (Console hoặc CLI) thành một mật khẩu mới, ví dụ `"mypassword2026"`.

### Bước 3: Nghiệm thu kết quả đồng bộ dưới 60s
1.  **Kiểm tra xem K8s Secret tự động đổi giá trị chưa**:
    ```bash
    kubectl get secret db-secret -n demo -o jsonpath='{.data.password}' | base64 -d; echo
    ```
    *Kỳ vọng*: Trả về `"mypassword2026"` trong vòng dưới 60 giây.
2.  **Kiểm tra xem Pod có bị restart không (Cột AGE và RESTARTS)**:
    ```bash
    kubectl get pods -n demo -l app=api
    ```
    *Kỳ vọng*: Cột **AGE** giữ nguyên (không bị reset về 0s), **RESTARTS** bằng 0.
3.  **Kiểm tra file mật khẩu được cập nhật trực tiếp bên trong Container**:
    ```bash
    kubectl exec -it $(kubectl get pods -n demo -l app=api -o jsonpath='{.items[0].metadata.name}') -n demo -- cat /etc/secrets/password
    ```
    *Kỳ vọng*: Nội dung in ra là `"mypassword2026"`.

---

## 6. Kiểm thử Lab 2.2 · Trivy + Cosign (Supply Chain Security)

### Kịch bản A: Thử deploy image chưa ký (Unsigned Image)
*   **Lệnh thực thi**:
    ```bash
    cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: Pod
    metadata:
      name: test-unsigned-image
      namespace: demo
    spec:
      containers:
      - name: web
        image: nginx:1.25
        resources: { limits: { cpu: 100m, memory: 64Mi } }
    EOF
    ```
*   **Kết quả kỳ vọng**: Yêu cầu bị Sigstore Policy Controller **chặn** lại:
    `admission webhook "policy.sigstore.dev" denied the request: validation failed: image nginx:1.25 signature verification failed`

### Kịch bản B: Deploy image đã ký hợp lệ từ CI
*   **Lệnh thực thi**:
    ```bash
    cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: Pod
    metadata:
      name: test-signed-image
      namespace: demo
    spec:
      containers:
      - name: api
        image: ghcr.io/ptienhocse/w10-api:<MÃ_PHIÊN_BẢN_ĐÃ_KÝ>
        resources: { limits: { cpu: 100m, memory: 64Mi } }
    EOF
    ```
*   **Kết quả kỳ vọng**: **Pass** (tạo thành công Pod).
