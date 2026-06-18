# HƯỚNG DẪN KIỂM THỬ TOÀN BỘ CÁC LABS (TEST GUIDE)

Tài liệu này cung cấp các kịch bản kiểm thử chi tiết, mã nguồn và câu lệnh mẫu để bạn có thể tự mình thực hiện kiểm thử và chứng minh hoạt động của toàn bộ Lab (RBAC, Gatekeeper, Argo Rollouts, Prometheus, Alertmanager).

---

## 1. Thông tin kết nối môi trường Lab

*   **Public IP của máy chủ EC2**: `18.141.231.240`
*   **Lệnh SSH kết nối trực tiếp (chạy từ thư mục gốc dự án)**:
    ```bash
    ssh -i "terraform/security-lab-key.pem" ubuntu@18.141.231.240
    ```
*   **Truy cập ArgoCD Web UI**: [https://18.141.231.240:8443](https://18.141.231.240:8443)
    *   **Tài khoản đăng nhập**: `admin`
    *   **Lệnh lấy mật khẩu quản trị (chạy trên EC2)**:
        ```bash
        kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
        ```

---

## 2. Kịch bản Lab 1: Kiểm thử Phân quyền RBAC

Sau khi kết nối SSH vào EC2, chạy các lệnh sau để kiểm tra cơ chế kiểm soát truy cập dựa trên vai trò (RBAC):

### Bước 1: Kiểm thử tài khoản `alice` (Developer của namespace `demo`)
*   **Yêu cầu**: Alice phải có toàn quyền CRUD các workloads trong namespace `demo` nhưng không được phép thao tác ở namespace khác (ví dụ: `kube-system`).
*   **Lệnh kiểm thử 1 (Mong đợi kết quả: `yes`)**:
    ```bash
    kubectl auth can-i create deployment -n demo --as alice
    ```
*   **Lệnh kiểm thử 2 (Mong đợi kết quả: `no`)**:
    ```bash
    kubectl auth can-i create deployment -n kube-system --as alice
    ```

### Bước 2: Kiểm thử tài khoản `bob` (SRE toàn hệ thống)
*   **Yêu cầu**: Bob được quyền giám sát và can thiệp debug (logs, port-forward, exec) trên toàn cụm nhưng không có quyền xóa nodes.
*   **Lệnh kiểm thử 1 (Mong đợi kết quả: `yes`)**:
    ```bash
    kubectl auth can-i get pods -A --as bob
    ```
*   **Lệnh kiểm thử 2 (Mong đợi kết quả: `no`)**:
    ```bash
    kubectl auth can-i delete nodes --as bob
    ```

### Bước 3: Kiểm thử tài khoản `carol` (Viewer toàn cụm)
*   **Yêu cầu**: Carol chỉ có quyền đọc (read-only) và không thể thay đổi bất kỳ tài nguyên nào.
*   **Lệnh kiểm thử 1 (Mong đợi kết quả: `yes`)**:
    ```bash
    kubectl auth can-i list services -A --as carol
    ```
*   **Lệnh kiểm thử 2 (Mong đợi kết quả: `no`)**:
    ```bash
    kubectl auth can-i create pod -n demo --as carol
    ```

---

## 3. Kịch bản Lab 2: Kiểm thử OPA Gatekeeper Policies

Hãy thử tạo các Pod/Deployment vi phạm các quy tắc bảo mật trong namespace `demo` để kiểm tra khả năng chặn lọc của OPA Gatekeeper:

### Chính sách 1: Cấm tag `:latest` (`block-latest-tag`)
*   **Kịch bản**: Tạo Pod sử dụng ảnh `nginx:latest`.
*   **Lệnh thực thi**:
    ```bash
    cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: Pod
    metadata:
      name: test-latest-tag
      namespace: demo
    spec:
      containers:
      - name: web
        image: nginx:latest
        resources:
          limits:
            cpu: 100m
            memory: 64Mi
    EOF
    ```
*   **Kết quả mong đợi**: Gatekeeper từ chối yêu cầu với thông báo lỗi:
    `[block-latest-tag] container <web> has disallowed image tag <latest> in image <nginx:latest>`

### Chính sách 2: Bắt buộc cấu hình Resource Limits (`require-resource-limits`)
*   **Kịch bản**: Tạo Pod không khai báo limits cho CPU và Memory.
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
*   **Kết quả mong đợi**: Gatekeeper từ chối yêu cầu với thông báo lỗi:
    `[require-resource-limits] container <web> does not have resource limit <cpu>` (và `<memory>`)

### Chính sách 3: Cấm chạy với quyền Root (`block-root-user`)
*   **Kịch bản**: Tạo Pod có khai báo `runAsUser: 0`.
*   **Lệnh thực thi**:
    ```bash
    cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: Pod
    metadata:
      name: test-root-user
      namespace: demo
    spec:
      securityContext:
        runAsUser: 0
      containers:
      - name: web
        image: nginx:1.25
        resources:
          limits:
            cpu: 100m
            memory: 64Mi
    EOF
    ```
*   **Kết quả mong đợi**: Gatekeeper từ chối yêu cầu với thông báo lỗi:
    `[block-root-user] Pod securityContext runAsUser is set to 0 (root)`

### Chính sách 4: Cấm sử dụng mạng của Host (`block-host-network`)
*   **Kịch bản**: Tạo Pod khai báo `hostNetwork: true`.
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
        resources:
          limits:
            cpu: 100m
            memory: 64Mi
    EOF
    ```
*   **Kết quả mong đợi**: Gatekeeper từ chối yêu cầu với thông báo lỗi:
    `[block-host-network] Sharing the host network namespace is not allowed (hostNetwork: true)`

### Chính sách 5: Giới hạn replicas tối đa (`limit-max-replicas`)
*   **Kịch bản**: Tạo Deployment trong namespace `demo` có `replicas: 6` (vượt ngưỡng 5).
*   **Lệnh thực thi**:
    ```bash
    cat <<EOF | kubectl apply -f -
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: test-max-replicas
      namespace: demo
    spec:
      replicas: 6
      selector:
        matchLabels:
          app: web
      template:
        metadata:
          labels:
            app: web
        spec:
          containers:
          - name: web
            image: nginx:1.25
            resources:
              limits:
                cpu: 100m
                memory: 64Mi
    EOF
    ```
*   **Kết quả mong đợi**: Gatekeeper từ chối yêu cầu với thông báo lỗi:
    `[limit-max-replicas] Workload replicas count 6 exceeds the maximum allowed replica count of 5`

---

## 4. Kịch bản Lab 3: Kiểm thử Progressive Delivery (Argo Rollouts)

Chúng ta sẽ mô phỏng các đợt cập nhật phần mềm (GitOps) để kiểm tra hoạt động phân tích tự động (AnalysisTemplate) và cơ chế tự động Rollback.

### Kịch bản A: Deploy Phiên bản lỗi (Trigger Tự Động Rollback)
Chúng ta sẽ giả lập một đợt triển khai lỗi với tỷ lệ HTTP Error Rate là 15% (Success Rate chỉ đạt 85%, dưới ngưỡng yêu cầu 90%).

1.  **Chạy trên máy local của bạn**:
    Mở file `app-api/rollout.yaml` và chỉnh sửa tham số `ERROR_RATE` lên `0.15`:
    ```yaml
    # Dòng 32-33:
    - name: ERROR_RATE
      value: "0.15"
    ```
2.  **Commit & Push lên GitHub**:
    ```bash
    git add app-api/rollout.yaml
    git commit -m "test: deploy v0.0.1 with 15% error rate"
    git push origin main
    ```
3.  **Quan sát quá trình tự động Rollback (Chạy trên EC2)**:
    Khi ArgoCD nhận biết commit mới, nó sẽ tự động đồng bộ hóa phiên bản lỗi này lên cụm.
    *   **Theo dõi tiến trình Rollout**:
        ```bash
        kubectl argo rollouts get rollout api -n demo
        ```
    *   **Theo dõi các đợt phân tích metrics (AnalysisRun)**:
        ```bash
        kubectl get analysisrun -n demo -w
        ```
    Sau khoảng 2-3 phút, khi Prometheus ghi nhận success rate trung bình giảm xuống dưới 90% quá 3 lần kiểm tra (Failure Limit), Argo Rollouts sẽ tự động chuyển đổi trạng thái của đợt triển khai thành `Degraded` và **tự động chuyển hướng 100% traffic trở lại phiên bản ổn định cũ**.

### Kịch bản B: Deploy Phiên bản thành công
Khi bạn muốn triển khai phiên bản ổn định hoàn chỉnh (HTTP Error Rate bằng 0%):

1.  **Chạy trên máy local của bạn**:
    Sửa lại tham số `ERROR_RATE` về `0` trong `app-api/rollout.yaml`:
    ```yaml
    - name: ERROR_RATE
      value: "0"
    ```
2.  **Commit & Push lên GitHub**:
    ```bash
    git add app-api/rollout.yaml
    git commit -m "deploy: deploy stable v0.0.1 with 0% error rate"
    git push origin main
    ```
3.  **Quan sát (Chạy trên EC2)**:
    Theo dõi qua câu lệnh:
    ```bash
    kubectl argo rollouts get rollout api -n demo
    ```
    Hệ thống sẽ hoàn thành các bước 10% -> 50% -> 100% traffic một cách an toàn mà không bị hủy bỏ giữa chừng.
