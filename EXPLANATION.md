# TÀI LIỆU GIẢI THÍCH CHI TIẾT LAB 1: RBAC + GATEKEEPER (MẤT GỐC VẪN HIỂU)

Tài liệu này được biên soạn đặc biệt dành cho người mới bắt đầu hoặc người đã quên kiến thức cơ bản về Kubernetes, GitOps và Bảo mật. Tài liệu được cấu trúc như sau:
*   **Phần A: Từ điển thuật ngữ chuyên ngành (Đọc để hiểu các từ khóa)**
*   **Phần B: Nhật ký các câu lệnh đã chạy thực tế trong Lab**
*   **Phần C: Giải thích chi tiết từng Lab (Lab 1.1, 1.2, 1.3) kèm phân tích mã nguồn từng dòng**

---

## PHẦN A: TỪ ĐIỂN THUẬT NGỮ CHUYÊN NGÀNH

Trước khi đọc hiểu mã nguồn, bạn cần nắm vững các định nghĩa cơ bản dưới đây:

### 1. Thuật ngữ về hạ tầng & K8s cơ bản
*   **VPC (Virtual Private Cloud - Mạng ảo riêng)**: Là một vùng mạng riêng cô lập được tạo ra trên nền tảng đám mây (AWS). Nó giúp bảo vệ máy chủ của bạn khỏi các truy cập trái phép từ Internet.
*   **EC2 Instance (Elastic Compute Cloud)**: Một máy chủ ảo (giống như một chiếc máy tính chạy hệ điều hành Ubuntu) được thuê trên đám mây AWS.
*   **Kubernetes (K8s)**: Hệ thống quản lý và điều phối các ứng dụng được đóng gói dưới dạng Container (như Docker). Thay vì chạy ứng dụng trực tiếp trên máy chủ, K8s giúp tự động hóa việc triển khai, mở rộng và quản trị các Container này trên một cụm máy chủ.
*   **Kind (Kubernetes in Docker)**: Công cụ giúp tạo nhanh một cụm Kubernetes giả lập chạy trực tiếp trong các Docker Containers trên chính máy EC2 của bạn.
*   **Namespace (Không gian tên)**: Giống như một ngăn tủ hoặc thư mục trong máy tính. K8s dùng Namespace để phân chia tài nguyên cụm thành các vùng độc lập (ví dụ: namespace `demo` cho ứng dụng thử nghiệm, namespace `kube-system` cho hệ thống cốt lõi).
*   **Pod**: Đơn vị nhỏ nhất và là cơ bản nhất trong Kubernetes để chạy ứng dụng của bạn. Một Pod chứa một hoặc nhiều Container chạy chung một mạng và ổ đĩa.
*   **Deployment**: Một bộ điều khiển trong K8s quản lý việc tạo ra và cập nhật các Pod. Nó định nghĩa số lượng bản sao (replicas), phiên bản ứng dụng, v.v.
*   **Rollout**: Một khái niệm mở rộng (nhờ công cụ Argo Rollouts) giúp cập nhật ứng dụng theo các chiến lược phức tạp hơn (như Canary - chuyển dần traffic từ 10% -> 50% -> 100%).
*   **Replicas**: Số lượng bản sao (số lượng Pod) chạy song song của cùng một ứng dụng để chia tải và phòng ngừa sự cố.

### 2. Thuật ngữ về GitOps & ArgoCD
*   **GitOps**: Phương pháp quản lý hạ tầng và deploy ứng dụng mà ở đó **Git là nguồn chân lý duy nhất (Source of Truth)**. Lập trình viên chỉ cần thay đổi file cấu hình YAML trên Git, hệ thống sẽ tự động cập nhật lên Kubernetes cluster mà không cần chạy lệnh thủ công.
*   **ArgoCD**: Công cụ thực hiện GitOps chạy trong cụm K8s. Nó liên tục theo dõi Git Repository của bạn, so sánh cấu hình trên Git với trạng thái thực tế trên K8s cluster. Nếu có sự khác biệt (OutOfSync), nó sẽ tự động đồng bộ (Sync) để đưa cluster về đúng trạng thái trên Git.
*   **App of Apps Pattern (Mô hình Ứng dụng của các Ứng dụng)**: Thiết kế phân cấp trong ArgoCD. Ta tạo một ứng dụng gốc (Root App), ứng dụng này sẽ tự động khai báo và quản lý các ứng dụng con khác bằng cách quét một thư mục cấu hình trên Git.

### 3. Thuật ngữ về Phân quyền (RBAC)
*   **RBAC (Role-Based Access Control)**: Cơ chế kiểm soát truy cập dựa trên vai trò. Nó trả lời cho câu hỏi: **Ai (Subject) được phép làm gì (Verbs) trên tài nguyên nào (Resources)?**
*   **Role**: Danh sách quyền hạn thao tác (create, delete, get...) trên các tài nguyên trong phạm vi **chỉ 1 Namespace**.
*   **ClusterRole**: Giống như Role nhưng có phạm vi áp dụng trên **toàn bộ cụm K8s** (ở tất cả các Namespaces, bao gồm cả các tài nguyên toàn cụm như Node, Namespace).
*   **RoleBinding**: Tấm dây liên kết gán một **Role** cho một Người dùng/Nhóm cụ thể trong phạm vi 1 Namespace.
*   **ClusterRoleBinding**: Tấm dây liên kết gán một **ClusterRole** cho một Người dùng/Nhóm cụ thể trên toàn bộ cụm.
*   **Impersonation (Giả lập người dùng)**: Tính năng của K8s (sử dụng cờ `--as <user>`) giúp quản trị viên (admin) chạy lệnh với tư cách của một người dùng khác để kiểm tra xem phân quyền của họ đã chuẩn hay chưa.

### 4. Thuật ngữ về OPA Gatekeeper & Policy Enforcement
*   **Admission Controller**: Một bộ lọc của Kubernetes API Server. Khi bạn gửi yêu cầu tạo tài nguyên (ví dụ: `kubectl apply -f pod.yaml`), Admission Controller sẽ chặn yêu cầu này lại để kiểm tra và chỉnh sửa trước khi lưu vào cơ sở dữ liệu của cụm.
*   **OPA (Open Policy Agent) Gatekeeper**: Công cụ giúp viết các luật bảo mật đầu vào cho cụm K8s bằng cơ chế Admission Controller.
*   **ConstraintTemplate**: Định nghĩa ra **Logic kiểm tra** cấu hình YAML xem có hợp lệ không. Logic này được viết bằng ngôn ngữ lập trình khai báo **Rego**.
*   **Constraint**: Sử dụng các luật kiểm tra từ ConstraintTemplate để áp dụng lên các đối tượng cụ thể (ví dụ: Áp dụng luật Max Replicas cho namespace `demo` với tham số max = 5).
*   **Rego**: Ngôn ngữ lập trình khai báo được sử dụng bởi OPA để đánh giá các chính sách bảo mật. Cú pháp Rego tập trung vào việc tìm kiếm các trường hợp **vi phạm (violation)**. Nếu tìm thấy vi phạm, Gatekeeper sẽ reject yêu cầu đó.
*   **Image Tag `:latest`**: Nhãn phiên bản mặc định khi không chỉ định version cho container image. Đây là rủi ro bảo mật vì phiên bản có thể bị thay đổi âm thầm trên Registry.
*   **Resource Limits (CPU/Memory Limits)**: Giới hạn tối đa tài nguyên CPU và RAM mà một Container được phép tiêu thụ. Nó giúp tránh việc một container bị lỗi chiếm hết tài nguyên của toàn bộ Node vật lý.
*   **hostNetwork**: Cấu hình cho phép container sử dụng trực tiếp card mạng vật lý của Node máy chủ. Nếu bật tính năng này, container có thể nghe trộm các traffic mạng của các container khác trên cùng Node.
*   **runAsUser (UID)**: Định danh ID của người dùng chạy ứng dụng bên trong container. UID = 0 đại diện cho người dùng **Root** (quyền cao nhất). Nếu hacker xâm nhập được vào container chạy quyền root, họ có nguy cơ chiếm quyền kiểm soát toàn bộ máy chủ vật lý.

---

## PHẦN B: NHẬT KÝ CÁC CÂU LỆNH ĐÃ CHẠY TRÊN HỆ THỐNG

Dưới đây là các lệnh thực tế được thực thi trong quá trình triển khai Lab:

### 1. Lệnh hạ tầng (Chạy tại máy Client - Windows)
```powershell
# Khởi tạo Terraform để tải các thư viện của AWS provider
terraform init

# Triển khai hạ tầng (VPC, Security Group, EC2) lên AWS
terraform apply -auto-approve

# Thiết lập quyền hạn file key PEM trên Windows để SSH bảo mật
icacls.exe .\security-lab-key.pem /inheritance:r
icacls.exe .\security-lab-key.pem /grant:r "${env:USERNAME}:R"

# Copy file nén chứa code dự án lên máy chủ EC2
scp -o StrictHostKeyChecking=no -i security-lab-key.pem project.zip ubuntu@18.141.231.240:/home/ubuntu/
```

### 2. Lệnh vận hành Lab (Chạy trên máy chủ EC2 qua SSH)
```powershell
# Giải nén mã nguồn dự án
unzip -o /home/ubuntu/project.zip -d /home/ubuntu/aws-sercurity

# Khởi chạy Root Application để ArgoCD tự động tạo các app con
kubectl apply -f /home/ubuntu/aws-sercurity/argocd/root.yaml

# Khắc phục lỗi bất tuần tự bằng cách cài đặt trước các ConstraintTemplates
kubectl apply -f /home/ubuntu/aws-sercurity/gatekeeper/templates

# Đăng ký Secret chứa mật khẩu Alertmanager để tránh lỗi crash-loop
kubectl create secret generic alertmanager-email -n monitoring --from-literal=password=dummy-gmail-app-password-16-chars

# Xóa pod Alertmanager cũ để nó tự động khởi động lại và nhận Secret
kubectl delete pod alertmanager-kube-prometheus-stack-alertmanager-0 -n monitoring
```

---

## PHẦN C: GIẢI THÍCH CHI TIẾT TỪNG LAB KÈM PHÂN TÍCH CODE

---

### LAB 1.1 · PHÂN QUYỀN RBAC QUA GITOPS

#### 1. Yêu cầu của đề bài
Tạo 3 vai trò và gán cho 3 người dùng khác nhau qua cấu hình Git (không gõ lệnh apply thủ công):
1.  **Alice**: Là nhà phát triển ứng dụng (developer). Alice có toàn quyền (tạo, sửa, xóa, xem) các tài nguyên workloads (pod, deployment, service, rollout...) nhưng **chỉ được phép thực hiện bên trong Namespace tên là `demo`**.
2.  **Bob**: Kỹ sư vận hành hệ thống (SRE). Bob được phép xem và can thiệp debug (logs, port-forward, exec) trên các Pod ở **tất cả mọi namespace trên hệ thống cluster**.
3.  **Carol**: Người giám sát (viewer). Carol chỉ có quyền đọc (get, list, watch) mọi tài nguyên trên **toàn bộ cluster** và không được phép chỉnh sửa hay xóa bất cứ thứ gì.

#### 2. Phân tích mã nguồn Roles (`rbac/roles.yaml`)

Chúng ta chia làm 3 khối định nghĩa:

```yaml
# KHỐI 1: Định nghĩa quyền hạn cho Alice
apiVersion: rbac.authorization.k8s.io/v1 # Phiên bản API của hệ thống RBAC trong K8s
kind: Role                               # Định nghĩa đối tượng thuộc loại "Role" (phạm vi Namespace)
metadata:
  name: developer-role                   # Tên của Role này
  namespace: demo                        # GIỚI HẠN: Quyền hạn này chỉ có hiệu lực bên trong namespace "demo"
rules:
- apiGroups: ["", "apps", "batch", "argoproj.io"] # Các nhóm tài nguyên trong Kubernetes
  resources: ["pods", "pods/log", "pods/exec", "services", "endpoints", "configmaps", "secrets", "deployments", "replicasets", "statefulsets", "daemonsets", "jobs", "cronjobs", "rollouts"] # Danh sách các tài nguyên Alice được sờ vào
  verbs: ["*"]                           # Ký tự "*" nghĩa là được làm tất cả mọi hành động (create, delete, list, get, update...)
```

```yaml
# KHỐI 2: Định nghĩa quyền hạn cho Bob
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole                        # Sử dụng "ClusterRole" vì Bob cần thao tác xuyên suốt mọi namespace
metadata:
  name: sre-role                         # Tên của ClusterRole (không khai báo namespace vì có phạm vi toàn cụm)
rules:
- apiGroups: [""]                        # Nhóm tài nguyên lõi (core group)
  resources: ["pods", "pods/log", "pods/exec", "pods/portforward", "pods/status"] # Chỉ cho phép tương tác trực tiếp trên Pod để debug
  verbs: ["*"]                           # Được toàn quyền thực hiện trên Pod (exec, get logs, delete pod...)
```

```yaml
# KHỐI 3: Định nghĩa quyền hạn cho Carol
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole                        # Cần xem toàn bộ cụm nên sử dụng "ClusterRole"
metadata:
  name: viewer-role
rules:
- apiGroups: ["*"]                       # Dấu "*" ở apiGroups nghĩa là áp dụng cho mọi nhóm tài nguyên trong K8s
  resources: ["*"]                       # Dấu "*" ở resources nghĩa là áp dụng cho mọi loại tài nguyên
  verbs: ["get", "list", "watch"]         # GIỚI HẠN CHỈ ĐỌC: Chỉ được get, list, watch. Cấm tuyệt đối create, delete, update.
```

#### 3. Phân tích mã nguồn RoleBindings (`rbac/rolebindings.yaml`)

File này thực hiện việc "buộc" người dùng cụ thể vào các vai trò đã khai báo ở trên:

```yaml
# LIÊN KẾT 1: Gán quyền cho Alice
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding                        # Dùng RoleBinding để giới hạn Alice trong namespace
metadata:
  name: alice-developer-binding
  namespace: demo                        # Alice chỉ có quyền trong demo
subjects:
- kind: User                             # Đối tượng là một Người dùng thực tế
  name: alice                            # Tên người dùng là alice
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role                             # Trỏ đến Role đã định nghĩa ở Roles.yaml
  name: developer-role
  apiGroup: rbac.authorization.k8s.io
```

```yaml
# LIÊN KẾT 2: Gán quyền cho Bob
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding                 # Dùng ClusterRoleBinding vì sre-role là một ClusterRole
metadata:
  name: bob-sre-binding
subjects:
- kind: User
  name: bob
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole                      # Trỏ đến ClusterRole sre-role
  name: sre-role
  apiGroup: rbac.authorization.k8s.io
```

*   **Carol**: Cấu hình tương tự Bob, sử dụng `ClusterRoleBinding` để liên kết người dùng `carol` với ClusterRole `viewer-role`.

---

### LAB 1.2 · CÀI ĐẶT OPA GATEKEEPER & 4 LUẬT CHẶN ADMISSION

#### 1. Yêu cầu của đề bài
Triển khai hệ thống OPA Gatekeeper để tự động rà soát cấu hình YAML của bất kỳ ai gửi lên API Server. Nếu manifest vi phạm 1 trong 4 lỗi sau, API Server phải lập tức báo lỗi và chặn lại:
1.  **Cấm dùng image tag `:latest` hoặc không ghi rõ tag**: Buộc nhà phát triển phải ghim cứng phiên bản cụ thể (ví dụ: `nginx:1.25`).
2.  **Bắt buộc có giới hạn CPU/RAM (`resources.limits`)**: Ngăn chặn tình trạng tranh chấp tài nguyên trên Node vật lý.
3.  **Cấm chạy container bằng quyền Root (`runAsUser: 0`)**: Phòng tránh rủi ro hacker thoát container chiếm máy chủ.
4.  **Cấm sử dụng mạng chung của Host (`hostNetwork: true`)**: Đảm bảo cô lập mạng giữa các Pod.

#### 2. Cài đặt Controller (`argocd/apps/gatekeeper.yaml`)
Chúng ta sử dụng ArgoCD để cài đặt Helm chart của Gatekeeper vào namespace `gatekeeper-system` với sync-wave sớm hơn các ứng dụng khác.

#### 3. Phân tích chi tiết logic code Rego trong các Templates và Constraints

##### Luật 1: Cấm tag `:latest`
*   **Template (`gatekeeper/templates/k8sdisallowedtags-template.yaml`)**:
    ```rego
    package k8sdisallowedtags

    violation[{"msg": msg}] {
      # Lấy danh sách tất cả các containers khai báo trong Pod
      container := input_containers[_]
      image := container.image
      
      # Kiểm tra lỗi 1: Tên image không có dấu ":" (K8s sẽ tự hiểu là latest)
      not contains(image, ":")
      msg := sprintf("Container <%v> has no image tag specified", [container.name])
    }

    violation[{"msg": msg}] {
      container := input_containers[_]
      image := container.image
      
      # Kiểm tra lỗi 2: Tên image kết thúc bằng ":latest"
      endswith(image, ":latest")
      msg := sprintf("Container <%v> has disallowed image tag <latest> in image <%v>", [container.name, image])
    }

    # Hàm phụ để gom cả container chạy thường, container khởi động (init) và container tạm thời (ephemeral)
    input_containers[c] {
      c := input.review.object.spec.containers[_]
    }
    input_containers[c] {
      c := input.review.object.spec.initContainers[_]
    }
    ```
*   **Constraint (`gatekeeper/constraints/k8sdisallowedtags-constraint.yaml`)**:
    ```yaml
    apiVersion: constraints.gatekeeper.sh/v1beta1
    kind: K8sDisallowedTags                  # Loại luật (lấy từ spec.names.kind của Template)
    metadata:
      name: block-latest-tag
      annotations:
        argocd.argoproj.io/sync-wave: "2"    # Chạy sau khi Template đã sync thành công
    spec:
      match:
        kinds:
          - apiGroups: [""]
            kinds: ["Pod"]                  # Áp dụng kiểm tra đối với mọi đối tượng là Pod
        namespaces:
          - demo                           # Giới hạn áp dụng trong namespace "demo"
    ```

##### Luật 2: Bắt buộc cấu hình Resource Limits
*   **Template (`gatekeeper/templates/k8srequiredresources-template.yaml`)**:
    ```rego
    package k8srequiredresources

    # Báo lỗi nếu container không có trường resources.limits.cpu
    violation[{"msg": msg}] {
      container := input_containers[_]
      not container.resources.limits.cpu
      msg := sprintf("container <%v> does not have resource limit <cpu>", [container.name])
    }

    # Báo lỗi nếu container không có trường resources.limits.memory
    violation[{"msg": msg}] {
      container := input_containers[_]
      not container.resources.limits.memory
      msg := sprintf("container <%v> does not have resource limit <memory>", [container.name])
    }
    ```
*   **Constraint**: Áp dụng luật `K8sRequiredResources` lên tài nguyên Pod trong namespace `demo`.

##### Luật 3: Cấm chạy container bằng tài khoản Root (`runAsUser: 0`)
*   **Template (`gatekeeper/templates/k8sblockrootuser-template.yaml`)**:
    ```rego
    package k8sblockrootuser

    # Trường hợp 1: securityContext cấu hình ở cấp độ Pod có runAsUser = 0
    violation[{"msg": msg}] {
      input.review.object.spec.securityContext.runAsUser == 0
      msg := "Pod securityContext runAsUser is set to 0 (root)"
    }

    # Trường hợp 2: securityContext cấu hình trực tiếp trên từng Container có runAsUser = 0
    violation[{"msg": msg}] {
      container := input_containers[_]
      container.securityContext.runAsUser == 0
      msg := sprintf("Container <%v> securityContext runAsUser is set to 0 (root)", [container.name])
    }
    ```
*   **Constraint**: Áp dụng luật `K8sBlockRootUser` lên tài nguyên Pod trong namespace `demo`.

##### Luật 4: Cấm HostNetwork (`block-host-network`)
*   **Template (`gatekeeper/templates/k8shostnetwork-template.yaml`)**:
    ```rego
    package k8shostnetwork

    # Kiểm tra nếu trường spec.hostNetwork có giá trị là true
    violation[{"msg": msg}] {
      input.review.object.spec.hostNetwork
      msg := "Sharing the host network namespace is not allowed (hostNetwork: true)"
    }
    ```
*   **Constraint**: Áp dụng luật `K8sHostNetwork` lên tài nguyên Pod trong namespace `demo`.

---

### LAB 1.3 · VIẾT CUSTOM POLICY (REGO) CHẶN REPLICAS > 5

#### 1. Lựa chọn bài toán
Đề bài cho phép tự chọn 1 trong 3 luật tùy biến. Chúng ta lựa chọn bài toán: **Từ chối (Reject) mọi Deployment hoặc Rollout nếu số lượng replicas khai báo vượt quá 5 trong namespace `demo`**.

#### 2. Phân tích chi tiết mã nguồn Template tự viết (`gatekeeper/templates/k8smaxreplicas-template.yaml`)

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8smaxreplicas                    # Tên của Constraint Template
  annotations:
    argocd.argoproj.io/sync-wave: "1"    # Khởi tạo định nghĩa CRD ở Wave 1
spec:
  crd:
    spec:
      names:
        kind: K8sMaxReplicas              # Tên Kind mới sẽ được đăng ký vào Kubernetes API
      validation:
        openAPIV3Schema:
          type: object
          properties:
            max:
              type: integer               # Khai báo cấu trúc tham số đầu vào tên là "max" (kiểu số nguyên)
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8smaxreplicas

        # Định nghĩa logic phát hiện vi phạm
        violation[{"msg": msg}] {
          # BƯỚC 1: Lấy thông số replicas từ cấu hình YAML người dùng gửi lên
          replicas := input.review.object.spec.replicas
          
          # BƯỚC 2: Đọc cấu hình tham số "max" được khai báo từ Constraint tương ứng
          max_allowed := input.parameters.max
          
          # BƯỚC 3: So sánh. Nếu replicas gửi lên lớn hơn mức cho phép
          replicas > max_allowed
          
          # BƯỚC 4: Tạo thông báo lỗi trả về cho người dùng
          msg := sprintf("Workload replicas count %v exceeds the maximum allowed replica count of %v", [replicas, max_allowed])
        }
```

#### 3. Phân tích chi tiết mã nguồn Constraint (`gatekeeper/constraints/k8smaxreplicas-constraint.yaml`)

File này cung cấp tham số thực tế và áp dụng luật tối đa replicas lên namespace `demo`:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sMaxReplicas                     # Loại luật tối đa replicas vừa khai báo ở Template
metadata:
  name: limit-max-replicas
  annotations:
    argocd.argoproj.io/sync-wave: "2"    # Chạy sau ở Wave 2 để đảm bảo CRD K8sMaxReplicas đã tồn tại
spec:
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment"]            # Áp dụng cho các Deployment
      - apiGroups: ["argoproj.io"]
        kinds: ["Rollout"]               # Áp dụng cho các Argo Rollouts
    namespaces:
      - demo                             # Áp dụng phạm vi trong namespace "demo"
  parameters:
    max: 5                               # GÁN THAM SỐ: Số replicas tối đa cho phép là 5
```
