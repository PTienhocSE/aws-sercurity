# GIẢI THÍCH KIẾN TRÚC & PHÂN TÍCH CODE CHI TIẾT (MAPPING LABS)

Tài liệu này giải thích chi tiết toàn bộ kiến trúc hệ thống, hạ tầng và phân tích từng dòng code của các chính sách bảo mật đã triển khai trong Lab: **RBAC + OPA Gatekeeper kết hợp Progressive Delivery (Argo Rollouts + Prometheus + ArgoCD)** trên hạ tầng AWS EC2.

---

## MỤC LỤC
1. [Hạ tầng IaC & Setup Server (Terraform & Scripts)](#1-hạ-tầng-iac--setup-server-terraform--scripts)
2. [Mô hình GitOps App of Apps (ArgoCD)](#2-mô-hình-gitops-app-of-apps-argocd)
3. [Phân quyền Role-Based Access Control (RBAC)](#3-phân-quyền-role-based-access-control-rbac)
4. [Kiểm soát Chính sách OPA Gatekeeper (Admission Control)](#4-kiểm-soát-chính-sách-opa-gatekeeper-admission-control)
5. [Quy trình Triển khai Canary & Phân tích Metrics (Argo Rollouts)](#5-quy-trình-triển-khai-canary--phân-tích-metrics-argo-rollouts)

---

## 1. Hạ tầng IaC & Setup Server (Terraform & Scripts)

### A. Khởi tạo tài nguyên trên AWS bằng Terraform (`terraform/`)
Chúng ta sử dụng Terraform để định nghĩa Infrastructure as Code (IaC), đảm bảo môi trường Lab sạch, cô lập và an toàn:
*   **VPC (`aws_vpc.security_lab_vpc`)**: Tạo một mạng ảo độc lập có CIDR `10.0.0.0/16`.
*   **Subnet (`aws_subnet.security_lab_subnet`)**: Khai báo mạng con công khai CIDR `10.0.1.0/24` tại Singapore (`ap-southeast-1a`), bật tính năng tự động gán IP công cộng (`map_public_ip_on_launch = true`).
*   **Internet Gateway & Route Table**: Tạo Gateway kết nối VPC ra Internet và định tuyến mọi traffic hướng ngoại qua Gateway này.
*   **Security Group (`aws_security_group.security_lab_sg`)**: Cấu hình quy tắc tường lửa:
    *   Cổng `22`: Cho phép SSH truy cập từ mọi nơi (`0.0.0.0/0`).
    *   Cổng `8443`: Expose ArgoCD Web UI ra bên ngoài.
    *   Cổng `8080`: Expose REST API của ứng dụng chính.
*   **EC2 Instance (`aws_instance.security_lab_ec2`)**: Spawning một máy ảo Ubuntu Server 22.04 LTS, cấu hình loại `t3.medium` (2 vCPUs, 4GB RAM) để đủ tài nguyên chạy cụm Kubernetes ảo, dung lượng lưu trữ SSD gp3 20GB.
*   **SSH Key Pair**: Tạo tự động SSH key pair `security-lab-key` và lưu trữ nội bộ dưới dạng PEM (`security-lab-key.pem`) trên máy client để SSH bảo mật.

### B. Cài đặt thành phần K8s bằng Script (`scripts/setup-ec2.sh`)
Sau khi EC2 khởi động, script `setup-ec2.sh` tự động hóa các bước cài đặt:
1.  **Docker & Kind (Kubernetes in Docker)**: Cài đặt Docker làm container runtime, sau đó dựng cụm K8s ảo thông qua Kind với cấu hình định tuyến (port forwarding) cổng `30080` (API) sang `8080` của EC2, và cổng `30443` (ArgoCD Server) sang `8443` của EC2.
2.  **Kubectl, Helm**: Cài đặt các công cụ quản lý cụm.
3.  **ArgoCD**: Cài đặt hệ thống GitOps điều phối cụm, mở rộng dịch vụ `argocd-server` dưới dạng NodePort trên cổng `30443`.

---

## 2. Mô hình GitOps App of Apps (ArgoCD)

Chúng ta triển khai mô hình **App of Apps pattern** để quản lý vòng đời của mọi tài nguyên trên cụm K8s chỉ qua một ứng dụng gốc là `root` (`argocd/root.yaml`).

### Phân tích `argocd/root.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/PTienhocSE/aws-sercurity.git
    path: argocd/apps       # Chỉ định ArgoCD quét thư mục con này để tìm các file App khác
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true          # Tự động xóa tài nguyên trên cụm nếu bị xóa trên Git
      selfHeal: true       # Tự động phục hồi tài nguyên nếu bị thay đổi thủ công trên cụm
```

### Quản lý thứ tự triển khai bằng Sync Waves:
Các file ứng dụng con trong `argocd/apps/` được gán thuộc tính `sync-wave` để triển khai tuần tự theo đúng thiết kế phụ thuộc hạ tầng:
1.  **Wave `-1` (`app-common.yaml`)**: Tạo Namespace `demo` trước.
2.  **Wave `0` (`k8s-rollout.yaml` & `k8s-prometheus.yaml`)**: Cài đặt controllers hạ tầng (Argo Rollouts controller, Prometheus Operator Stack).
3.  **Wave `1` (`gatekeeper.yaml` & `rbac.yaml`)**: Cài đặt Admission Controller Gatekeeper và các chính sách phân quyền Cluster Roles.
4.  **Wave `2` (`gatekeeper-policies.yaml` & `app-alert.yaml` & `app-analysis.yaml`)**: Áp dụng các luật bảo mật cụ thể (Constraints) sau khi OPA Gatekeeper Controller đã chạy.
5.  **Wave `2` (`app-api.yaml`)**: Triển khai ứng dụng API chính sau khi đảm bảo mọi luật bảo mật và hệ thống giám sát đã sẵn sàng chặn lọc.

---

## 3. Phân quyền Role-Based Access Control (RBAC)

RBAC đảm bảo nguyên tắc đặc quyền tối thiểu (Least Privilege) cho các kỹ sư vận hành trong hệ thống. File cấu hình gồm `rbac/roles.yaml` và `rbac/rolebindings.yaml`.

### Phân tích `rbac/roles.yaml`:
Chúng ta định nghĩa 3 nhóm quyền riêng biệt:

1.  **Quyền Developer (`developer-role` - Namespace Scope)**:
    ```yaml
    apiVersion: rbac.authorization.k8s.io/v1
    kind: Role
    metadata:
      name: developer-role
      namespace: demo    # Giới hạn quyền trong phạm vi namespace demo
    rules:
    - apiGroups: ["", "apps", "batch", "argoproj.io"]
      resources: ["pods", "pods/log", "pods/exec", "services", "endpoints", "configmaps", "secrets", "deployments", "replicasets", "statefulsets", "daemonsets", "jobs", "cronjobs", "rollouts"]
      verbs: ["*"]      # Đầy đủ quyền CRUD với các workloads ứng dụng
    ```
2.  **Quyền SRE (`sre-role` - Cluster Scope)**:
    ```yaml
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRole
    metadata:
      name: sre-role
    rules:
    - apiGroups: [""]
      resources: ["pods", "pods/log", "pods/exec", "pods/portforward", "pods/status"]
      verbs: ["*"]      # Quyền debug hệ thống toàn cụm, can thiệp xử lý Pod trực tiếp
    ```
3.  **Quyền Viewer (`viewer-role` - Cluster Scope)**:
    ```yaml
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRole
    metadata:
      name: viewer-role
    rules:
    - apiGroups: ["*"]
      resources: ["*"]
      verbs: ["get", "list", "watch"] # Chỉ cho phép đọc thông tin trên toàn bộ cụm, cấm thay đổi
    ```

### Phân tích `rbac/rolebindings.yaml`:
Liên kết người dùng thực tế với quyền hạn tương ứng:
*   `alice` gắn liền với `developer-role` tại namespace `demo` thông qua `RoleBinding`.
*   `bob` gắn liền với `sre-role` trên toàn cụm thông qua `ClusterRoleBinding`.
*   `carol` gắn liền với `viewer-role` trên toàn cụm thông qua `ClusterRoleBinding`.

---

## 4. Kiểm soát Chính sách OPA Gatekeeper (Admission Control)

OPA Gatekeeper chặn đứng các khai báo cấu hình Pod không an toàn ngay tại cửa ngõ API Server bằng cơ chế Validation Webhook. Mỗi chính sách bảo mật bao gồm **ConstraintTemplate** (Khai báo logic bằng Rego) và **Constraint** (Chỉ định đối tượng áp dụng).

### 1. Cấm tag `:latest` hoặc không tag (`block-latest-tag`)
*   **Logic Rego (`k8sdisallowedtags-template.yaml`)**:
    Kiểm tra tên image của container. Nếu image không chứa dấu hai chấm `:` (nghĩa là mặc định không khai báo tag sẽ hiểu là latest) hoặc chứa tag `:latest` ở đuôi, hệ thống sẽ reject.
    ```rego
    violation[{"msg": msg}] {
      container := input_containers[_]
      image := container.image
      # Trường hợp 1: Không khai báo tag
      not contains(image, ":")
      msg := sprintf("Container <%v> has no image tag specified (will default to latest)", [container.name])
    }
    violation[{"msg": msg}] {
      container := input_containers[_]
      image := container.image
      # Trường hợp 2: Khai báo tag :latest
      endswith(image, ":latest")
      msg := sprintf("Container <%v> has disallowed image tag <latest> in image <%v>", [container.name, image])
    }
    ```

### 2. Bắt buộc cấu hình Resource Limits (`require-resource-limits`)
*   **Logic Rego (`k8srequiredresources-template.yaml`)**:
    Duyệt qua danh sách container, kiểm tra xem có khai báo `resources.limits.cpu` và `resources.limits.memory` hay không. Nếu thiếu bất kỳ thành phần nào, lệnh deploy sẽ bị từ chối nhằm ngăn chặn rủi ro tranh chấp tài nguyên (Noisy Neighbor).
    ```rego
    violation[{"msg": msg}] {
      container := input_containers[_]
      not container.resources.limits.cpu
      msg := sprintf("container <%v> does not have resource limit <cpu>", [container.name])
    }
    violation[{"msg": msg}] {
      container := input_containers[_]
      not container.resources.limits.memory
      msg := sprintf("container <%v> does not have resource limit <memory>", [container.name])
    }
    ```

### 3. Cấm chạy quyền Root (`block-root-user`)
*   **Logic Rego (`k8sblockrootuser-template.yaml`)**:
    Ngăn chặn nguy cơ leo thang đặc quyền (Privilege Escalation) bằng cách quét cấu hình `securityContext`. Nếu thiết lập `runAsUser == 0` ở cấp độ Pod hoặc Container, yêu cầu khởi tạo sẽ bị từ chối.
    ```rego
    violation[{"msg": msg}] {
      input.review.object.spec.securityContext.runAsUser == 0
      msg := "Pod securityContext runAsUser is set to 0 (root)"
    }
    violation[{"msg": msg}] {
      container := input_containers[_]
      container.securityContext.runAsUser == 0
      msg := sprintf("Container <%v> securityContext runAsUser is set to 0 (root)", [container.name])
    }
    ```

### 4. Cấm sử dụng HostNetwork (`block-host-network`)
*   **Logic Rego (`k8shostnetwork-template.yaml`)**:
    Ngăn chặn Pod truy cập trực tiếp vào network namespace của node vật lý bằng cách cấm khai báo `hostNetwork: true`.
    ```rego
    violation[{"msg": msg}] {
      input.review.object.spec.hostNetwork
      msg := "Sharing the host network namespace is not allowed (hostNetwork: true)"
    }
    ```

### 5. Custom Policy: Giới hạn tối đa Replicas (`limit-max-replicas`)
*   **Logic Rego (`k8smaxreplicas-template.yaml`)**:
    Khống chế quy mô tối đa của tài nguyên trong namespace `demo` bằng tham số động `max` được truyền từ Constraint. Logic Rego lấy số lượng `spec.replicas` so sánh với tham số truyền vào:
    ```rego
    violation[{"msg": msg}] {
      replicas := input.review.object.spec.replicas
      max_allowed := input.parameters.max
      replicas > max_allowed
      msg := sprintf("Workload replicas count %v exceeds the maximum allowed replica count of %v", [replicas, max_allowed])
    }
    ```
*   **Khai báo Constraint (`k8smaxreplicas-constraint.yaml`)**:
    Giới hạn Deployment và Rollout trong namespace `demo` tối đa chỉ được khai báo **5 replicas**:
    ```yaml
    spec:
      match:
        kinds:
          - apiGroups: ["apps"]
            kinds: ["Deployment"]
          - apiGroups: ["argoproj.io"]
            kinds: ["Rollout"]
        namespaces:
          - demo
      parameters:
        max: 5
    ```

---

## 5. Quy trình Triển khai Canary & Phân tích Metrics (Argo Rollouts)

Triển khai ứng dụng chính bằng **Progressive Delivery** thông qua Argo Rollouts, tự động đánh giá sức khỏe của phiên bản mới bằng Prometheus metrics trước khi đưa lên 100% traffic.

### A. Chiến lược Canary Release (`app-api/rollout.yaml`)
Canary chia lộ trình nâng cấp thành các bước nâng dần tỷ trọng traffic (sync-wave 0):
```yaml
spec:
  replicas: 2
  strategy:
    canary:
      analysis:
        templates:
          - templateName: success-rate # Liên kết với template đánh giá success rate
        startingStep: 1                # Bắt đầu chạy phân tích từ bước 1
      steps:
      - setWeight: 10                  # Chuyển 10% traffic sang phiên bản mới
      - pause: {duration: 2m}          # Dừng lại 2 phút để phân tích tự động chạy
      - setWeight: 50                  # Chuyển tiếp 50% traffic
      - pause: {duration: 2m}          # Tiếp tục dừng lại đánh giá 2 phút
      - setWeight: 100                 # Đạt 100% traffic nếu không có lỗi phát sinh
```

### B. Phân tích tự động bằng Prometheus (`app-analysis/analysis-template.yaml`)
`AnalysisTemplate` định nghĩa các truy vấn định kỳ vào Prometheus để tính toán tỷ lệ thành công của HTTP requests trên API:
```yaml
spec:
  metrics:
  - name: success-rate
    interval: 30s                      # Chạy kiểm tra mỗi 30 giây
    successCondition: result[0] >= 0.90 # Điều kiện thành công: tỷ lệ HTTP 2xx/3xx >= 90%
    failureLimit: 3                    # Cho phép tối đa 3 lần kiểm tra thất bại trước khi rollback
    provider:
      prometheus:
        address: http://kube-prometheus-stack-prometheus.monitoring.svc:9090
        query: |
          sum(rate(flask_http_request_total{status=~"[23].*",app="api"}[2m])) 
          / 
          sum(rate(flask_http_request_total{app="api"}[2m]))
```
*   **Cơ chế Rollback**: Nếu tỷ lệ thành công giảm xuống dưới 90% quá 3 lần, `AnalysisRun` sẽ chuyển trạng thái `Failed`, Argo Rollouts lập tức kéo sập phiên bản mới và chuyển 100% traffic về phiên bản ổn định trước đó (v0.0.1) nhằm giảm thiểu ảnh hưởng tới người dùng cuối.
*   **Cảnh báo SLO**: Nếu tỷ lệ thành công nằm trong khoảng từ `90%` đến `95%` (Canary vẫn pass vì ngưỡng pass là `90%`), PrometheusRules (`app-alert/prometheus-rules.yaml`) sẽ phát hiện tỷ lệ lỗi đang vi phạm SLO mục tiêu của hệ thống (95%) và kích hoạt cảnh báo thông qua **Alertmanager** để gửi email cảnh báo cho kỹ sư vận hành xử lý.
