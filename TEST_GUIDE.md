# HƯỚNG DẪN KIỂM THỬ LAB 1 (RBAC + GATEKEEPER)

Tài liệu này hướng dẫn cách chạy lệnh kiểm thử (nghiệm thu) cho từng phần của **Lab 1** trực tiếp trên cụm Kubernetes của máy chủ EC2.

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
*   **Kết quả kỳ vọng**: Bị **Reject** (API server từ chối tạo) với thông báo:
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
*   **Kết quả kỳ vọng**: **Pass** (tạo thành công pod trên hệ thống).
*   **Dọn dẹp**: `kubectl delete pod test-valid-pod -n demo`

---

## 4. Kiểm thử Lab 1.3 · Custom Policy (Giới hạn Replicas <= 5)

Chúng ta kiểm tra xem quy định giới hạn số replicas trong namespace `demo` hoạt động như thế nào:

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

### Kịch bản B: Thử deploy Deployment có 2 replicas (Hợp lệ)
*   **Lệnh thực thi**:
    ```bash
    cat <<EOF | kubectl apply -f -
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: test-replicas-2
      namespace: demo
    spec:
      replicas: 2
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
*   **Kết quả kỳ vọng**: **Pass** (tạo thành công deployment).
*   **Dọn dẹp**: `kubectl delete deployment test-replicas-2 -n demo`
