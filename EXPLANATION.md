# HƯỚNG DẪN GIẢI THÍCH CHI TIẾT LAB 1 & LAB 2 (DÀNH CHO NGƯỜI MẤT GỐC)

Tài liệu này giải thích chi tiết toàn bộ các phần của **Lab 1 (RBAC + Gatekeeper)** và **Lab 2 (Secrets + Supply Chain)**, bao gồm định nghĩa thuật ngữ, nhật ký lệnh, và phân tích code chi tiết từng dòng.

---

## BẢN ĐỒ MAPPING CÁC LABS
*   **Lab 1.1 · Phân quyền RBAC qua GitOps** -> [Xem Phần 1](#1-lab-11--phân-quyền-rbac-qua-gitops)
*   **Lab 1.2 · Cài đặt OPA Gatekeeper & 4 Luật chặn Admission** -> [Xem Phần 2](#2-lab-12--cài-đặt-opa-gatekeeper--4-luật-chặn-admission)
*   **Lab 1.3 · Viết Custom Policy (Rego) chặn Replicas > 5** -> [Xem Phần 3](#3-lab-13--viết-custom-policy-rego-chặn-replicas--5)
*   **Lab 2.1 · Xoay vòng Secrets không restart Pod (ESO)** -> [Xem Phần 4](#4-lab-21--xoay-vòng-secrets-không-restart-pod-eso)
*   **Lab 2.2 · Bảo mật chuỗi cung ứng (Trivy scan + Cosign sign + Policy Controller verify)** -> [Xem Phần 5](#5-lab-22--supply-chain-security-trivy--cosign)

---

## PHẦN A: TỪ ĐIỂN THUẬT NGỮ CHUYÊN NGÀNH

Trước khi đọc hiểu mã nguồn, bạn cần nắm vững các định nghĩa cơ bản dưới đây:

### 1. Thuật ngữ K8s cơ bản & Phân quyền RBAC (Lab 1.1)
*   **Namespace (Không gian tên)**: Giống như một ngăn tủ hoặc thư mục trong máy tính. K8s dùng Namespace để phân chia tài nguyên cụm thành các vùng độc lập (ví dụ: namespace `demo` cho ứng dụng chính, namespace `kube-system` cho hệ thống cốt lõi).
*   **Role**: Danh sách quyền hạn thao tác (create, delete, get...) trên các tài nguyên trong phạm vi **chỉ 1 Namespace**.
*   **ClusterRole**: Giống như Role nhưng có phạm vi áp dụng trên **toàn bộ cụm K8s** (ở tất cả các Namespaces).
*   **RoleBinding**: Tấm dây liên kết gán một **Role** cho một Người dùng/Nhóm cụ thể trong phạm vi 1 Namespace.
*   **ClusterRoleBinding**: Tấm dây liên kết gán một **ClusterRole** cho một Người dùng/Nhóm cụ thể trên toàn bộ cụm.
*   **Impersonation (Giả lập người dùng)**: Tính năng của K8s (sử dụng cờ `--as <user>`) giúp quản trị viên (admin) chạy lệnh với tư cách của một người dùng khác để kiểm tra phân quyền.

### 2. Thuật ngữ OPA Gatekeeper & Admission Control (Lab 1.2 & 1.3)
*   **Admission Controller**: Một bộ lọc của Kubernetes API Server. Khi bạn gửi yêu cầu tạo tài nguyên, Admission Controller sẽ chặn yêu cầu này lại để kiểm duyệt cấu hình trước khi lưu vào cơ sở dữ liệu của cụm.
*   **OPA Gatekeeper**: Công cụ giúp viết các luật bảo mật đầu vào cho cụm K8s.
*   **ConstraintTemplate**: Định nghĩa ra **Logic kiểm tra** cấu hình YAML (viết bằng ngôn ngữ lập trình khai báo **Rego**). Nó giống như khung quy định pháp luật.
*   **Constraint**: Sử dụng các luật kiểm tra từ ConstraintTemplate để áp dụng lên các đối tượng cụ thể (ví dụ: Áp dụng luật Max Replicas cho namespace `demo` với tham số max = 5).
*   **Rego**: Ngôn ngữ lập trình khai báo được sử dụng bởi OPA. Cú pháp Rego tập trung vào việc tìm kiếm các trường hợp **vi phạm (violation)**.
*   **Resource Limits**: Giới hạn tối đa CPU/RAM container được phép tiêu thụ để tránh tranh chấp phần cứng vật lý.
*   **hostNetwork**: Cho phép container dùng chung card mạng với máy chủ vật lý, tăng nguy cơ bị nghe trộm traffic mạng.
*   **runAsUser (UID)**: Định danh người dùng chạy bên trong container. UID = 0 là **Root** (quyền tối cao, rủi ro bảo mật rất lớn nếu bị hack).

### 3. Thuật ngữ về Secrets Rotation & External Secrets Operator (Lab 2.1)
*   **External Secrets Operator (ESO)**: Một công cụ mở rộng của Kubernetes. Nó liên tục kết nối với các kho lưu trữ Secret bên ngoài (như AWS Secrets Manager, HashiCorp Vault) để tự động lấy mật khẩu về và tạo ra K8s Secret cục bộ.
*   **SecretStore**: Tài nguyên định nghĩa **cách thức kết nối và xác thực** từ cụm K8s tới nhà cung cấp Secret bên ngoài (như cấu hình Region AWS và AWS Credentials).
*   **ExternalSecret**: Tài nguyên định nghĩa **loại Secret nào cần đồng bộ**, tần suất kiểm tra sự thay đổi (`refreshInterval`) và tên của K8s Secret đích cần tạo ra.
*   **Volume Mount Secret vs Env Variable**:
    *   Nếu đưa Secret vào container qua biến môi trường (Env Variable), khi Secret đổi giá trị, biến môi trường **không tự cập nhật**. Ta buộc phải restart Pod để nạp giá trị mới.
    *   Nếu đưa Secret vào container dưới dạng file trên đĩa cứng ảo (**Volume Mount**), dịch vụ Kubelet trên Node sẽ tự động đồng bộ giá trị mới vào file mà **không cần restart Pod** (Zero Downtime).

### 4. Thuật ngữ về Supply Chain Security, Trivy & Cosign (Lab 2.2)
*   **Vulnerability Scanning (Quét lỗ hổng)**: Kiểm tra các gói thư viện và hệ điều hành bên trong image xem có chứa các lỗ hổng bảo mật đã biết (CVE) hay không.
*   **Trivy**: Công cụ quét lỗ hổng mã nguồn mở cực kỳ phổ biến của Aqua Security.
*   **Cosign**: Công cụ nằm trong hệ sinh thái Sigstore, giúp ký số (sign) và xác minh (verify) chữ ký của các container image để chứng minh nguồn gốc xuất xứ của ảnh (tránh việc hacker thay đổi container image âm thầm).
*   **Sigstore Policy Controller**: Admission Controller chạy trong cụm K8s, chuyên dùng để kiểm tra chữ ký số của container image trước khi cho phép Pod khởi chạy.
*   **ClusterImagePolicy**: Khai báo chính sách kiểm tra chữ ký số trên cụm, định nghĩa dải hình ảnh cần quét và nội dung khóa công khai (Public Key) dùng để đối chiếu.

---

## PHẦN B: NHẬT KÝ CÁC CÂU LỆNH ĐÃ CHẠY TRÊN HỆ THỐNG

### 1. Lệnh hạ tầng và ký ảnh (Chạy tại máy Client - Windows)
```powershell
# Khởi tạo và áp dụng Terraform để tạo máy ảo EC2 trên AWS
terraform init
terraform apply -auto-approve

# Thiết lập quyền hạn file key PEM trên Windows để SSH bảo mật
icacls.exe .\security-lab-key.pem /inheritance:r
icacls.exe .\security-lab-key.pem /grant:r "${env:USERNAME}:R"

# Copy file nén chứa code dự án lên máy chủ EC2
scp -o StrictHostKeyChecking=no -i security-lab-key.pem project.zip ubuntu@18.141.231.240:/home/ubuntu/
```

### 2. Lệnh vận hành Lab (Chạy trên máy chủ EC2 qua SSH)
```bash
# Giải nén mã nguồn Lab
unzip -o /home/ubuntu/project.zip -d /home/ubuntu/aws-sercurity

# Triển khai cấu hình Root Application trong ArgoCD
kubectl apply -f /home/ubuntu/aws-sercurity/argocd/root.yaml

# Khắc phục lỗi bất tuần tự bằng cách cài đặt trước các ConstraintTemplates của Gatekeeper
kubectl apply -f /home/ubuntu/aws-sercurity/gatekeeper/templates

# Cài đặt công cụ Cosign trên EC2 để tạo cặp khóa ký ảnh
curl -Lo cosign https://github.com/sigstore/cosign/releases/download/v2.2.3/cosign-linux-amd64
chmod +x cosign
sudo mv cosign /usr/local/bin/

# Tạo cặp khóa ký ảnh non-interactive với mật khẩu bảo vệ
COSIGN_PASSWORD=mycosignpassword123 cosign generate-key-pair

# Tạo Secret chứa credentials AWS thủ công trên cụm (Không commit lên Git)
kubectl create secret generic aws-creds \
  -n demo \
  --from-literal=access-key="<YOUR_AWS_ACCESS_KEY>" \
  --from-literal=secret-key="<YOUR_AWS_SECRET_KEY>"
```

---

## PHẦN C: GIẢI THÍCH CHI TIẾT LAB 1 (RBAC + GATEKEEPER)

### 1. Lab 1.1 · Phân quyền RBAC qua GitOps

#### A. Yêu cầu của đề bài
Tạo 3 vai trò và gán cho 3 người dùng khác nhau qua cấu hình Git (không gõ lệnh apply thủ công):
*   **Alice**: Developer, có quyền CRUD các workloads (deployment, pod, service, rollout) chỉ trong namespace `demo`.
*   **Bob**: SRE, có quyền xem và thao tác debug (logs, port-forward, exec) trên Pod ở tất cả mọi namespace trên hệ thống.
*   **Carol**: Viewer, chỉ có quyền xem (get, list, watch) mọi tài nguyên trên toàn bộ cụm và không được phép chỉnh sửa hay xóa.

#### B. Phân tích mã nguồn Roles (`rbac/roles.yaml`)
```yaml
# Định nghĩa quyền cho Alice
apiVersion: rbac.authorization.k8s.io/v1
kind: Role                               # Đối tượng Role giới hạn trong Namespace demo
metadata:
  name: developer-role
  namespace: demo                        # GIỚI HẠN: Chỉ có hiệu lực trong namespace demo
rules:
- apiGroups: ["", "apps", "batch", "argoproj.io"]
  resources: ["pods", "pods/log", "pods/exec", "services", "endpoints", "configmaps", "secrets", "deployments", "replicasets", "statefulsets", "daemonsets", "jobs", "cronjobs", "rollouts"]
  verbs: ["*"]                           # Toàn quyền hành động (*)
---
# Định nghĩa quyền cho Bob
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole                        # Quyền toàn cụm
metadata:
  name: sre-role
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "pods/exec", "pods/portforward", "pods/status"]
  verbs: ["*"]                           # Toàn quyền trên các tài nguyên pod
---
# Định nghĩa quyền cho Carol
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole                        # Quyền toàn cụm
metadata:
  name: viewer-role
rules:
- apiGroups: ["*"]                       # Tất cả nhóm API
  resources: ["*"]                       # Tất cả tài nguyên
  verbs: ["get", "list", "watch"]         # GIỚI HẠN: Chỉ đọc, cấm chỉnh sửa
```

#### C. Phân tích mã nguồn RoleBindings (`rbac/rolebindings.yaml`)
```yaml
# Gán quyền cho Alice
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: alice-developer-binding
  namespace: demo
subjects:
- kind: User
  name: alice
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer-role
  apiGroup: rbac.authorization.k8s.io
---
# Gán quyền cho Bob
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: bob-sre-binding
subjects:
- kind: User
  name: bob
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: sre-role
  apiGroup: rbac.authorization.k8s.io
```
*(Tương tự, Carol được gắn vào `viewer-role` thông qua một `ClusterRoleBinding` toàn cụm).*

---

### 2. Lab 1.2 · Cài đặt OPA Gatekeeper & 4 Luật chặn Admission

#### A. Yêu cầu của đề bài
API Server phải chặn đứng các cấu hình YAML vi phạm 1 trong 4 lỗi sau:
1.  Cấm dùng image tag `:latest` hoặc không ghi rõ tag.
2.  Bắt buộc cấu hình limits cho CPU và RAM.
3.  Cấm chạy container bằng quyền root (`runAsUser: 0`).
4.  Cấm sử dụng card mạng của Host (`hostNetwork: true`).

#### B. Phân tích chi tiết logic code Rego trong các Templates và Constraints

##### Luật 1: Cấm tag `:latest`
*   **Template (`gatekeeper/templates/k8sdisallowedtags-template.yaml`)**:
    ```rego
    package k8sdisallowedtags

    violation[{"msg": msg}] {
      container := input_containers[_]
      image := container.image
      not contains(image, ":")      # Lỗi nếu thiếu dấu hai chấm (mặc định là latest)
      msg := sprintf("Container <%v> has no image tag specified", [container.name])
    }

    violation[{"msg": msg}] {
      container := input_containers[_]
      image := container.image
      endswith(image, ":latest")    # Lỗi nếu chỉ định tag latest
      msg := sprintf("Container <%v> has disallowed image tag <latest>", [container.name])
    }
    ```

##### Luật 2: Bắt buộc có Resource Limits
*   **Template (`gatekeeper/templates/k8srequiredresources-template.yaml`)**:
    ```rego
    package k8srequiredresources

    violation[{"msg": msg}] {
      container := input_containers[_]
      not container.resources.limits.cpu # Lỗi nếu thiếu CPU limit
      msg := sprintf("container <%v> does not have resource limit <cpu>", [container.name])
    }

    violation[{"msg": msg}] {
      container := input_containers[_]
      not container.resources.limits.memory # Lỗi nếu thiếu Memory limit
      msg := sprintf("container <%v> does not have resource limit <memory>", [container.name])
    }
    ```

##### Luật 3: Cấm chạy container bằng tài khoản Root (`runAsUser: 0`)
*   **Template (`gatekeeper/templates/k8sblockrootuser-template.yaml`)**:
    ```rego
    package k8sblockrootuser

    # Quét ở cấp độ Pod
    violation[{"msg": msg}] {
      input.review.object.spec.securityContext.runAsUser == 0
      msg := "Pod securityContext runAsUser is set to 0 (root)"
    }

    # Quét ở cấp độ Container
    violation[{"msg": msg}] {
      container := input_containers[_]
      container.securityContext.runAsUser == 0
      msg := sprintf("Container <%v> securityContext runAsUser is set to 0 (root)", [container.name])
    }
    ```

##### Luật 4: Cấm HostNetwork
*   **Template (`gatekeeper/templates/k8shostnetwork-template.yaml`)**:
    ```rego
    package k8shostnetwork

    violation[{"msg": msg}] {
      input.review.object.spec.hostNetwork
      msg := "Sharing the host network namespace is not allowed (hostNetwork: true)"
    }
    ```

---

### 3. Lab 1.3 · Viết Custom Policy (Rego) chặn Replicas > 5

#### A. Yêu cầu của đề bài
Tự viết một luật tùy biến bằng Rego. Chúng ta thiết lập: **Chặn đứng mọi Deployment/Rollout trong namespace `demo` có số replicas lớn hơn 5**.

#### B. Phân tích chi tiết code Rego tự viết (`gatekeeper/templates/k8smaxreplicas-template.yaml`)
```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8smaxreplicas
spec:
  crd:
    spec:
      names:
        kind: K8sMaxReplicas
      validation:
        openAPIV3Schema:
          type: object
          properties:
            max:
              type: integer               # Khai báo tham số đầu vào tên "max" kiểu số nguyên
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8smaxreplicas

        violation[{"msg": msg}] {
          replicas := input.review.object.spec.replicas
          max_allowed := input.parameters.max
          replicas > max_allowed         # Chặn nếu replicas vượt quá tham số cấu hình
          msg := sprintf("Workload replicas count %v exceeds the maximum allowed replica count of %v", [replicas, max_allowed])
        }
```

---

## PHẦN D: GIẢI THÍCH CHI TIẾT LAB 2 (SECRETS + SUPPLY CHAIN)

---

### 4. Lab 2.1 · Xoay vòng Secrets không restart Pod (ESO)

#### A. Nguyên lý hoạt động
Chúng ta chuyển dịch cấu hình từ việc lưu trữ Secret thủ công sang việc tích hợp tự động với **AWS Secrets Manager**.
*   **External Secrets Operator (ESO)** liên tục kết nối với AWS Secrets Manager qua secret `aws-creds` để đồng bộ mật khẩu của key `demo/db/password` về cụm K8s.
*   ESO cập nhật giá trị mới này vào Kubernetes Secret tên là `db-secret` trong namespace `demo` mỗi 10 giây (`refreshInterval: 10s`).
*   Pod của ứng dụng `api` được cấu hình mount `db-secret` dưới dạng một ổ đĩa ảo (**Volume**) tại `/etc/secrets/`. Do đó, khi mật khẩu thay đổi, Kubelet tự cập nhật nội dung file `/etc/secrets/password` mà không làm thay đổi trạng thái hoạt động của Pod, tránh hoàn toàn downtime và không làm tăng cột AGE của Pod.

#### B. Phân tích mã nguồn cấu hình

##### File `eso/secret-store.yaml` (Cấu hình kết nối AWS Secrets Manager):
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-store
  namespace: demo
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-southeast-1               # Region của AWS Secrets Manager
      auth:
        secretRef:                         # Trỏ đến Secret chứa thông tin AWS Keys
          accessKeyIDSecretRef:
            name: aws-creds                # Secret aws-creds được tạo thủ công (không commit)
            key: access-key
          secretAccessKeySecretRef:
            name: aws-creds
            key: secret-key
```

##### File `eso/external-secret.yaml` (Cấu hình đồng bộ secret):
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-creds
  namespace: demo
spec:
  refreshInterval: 10s                     # Tần suất kéo dữ liệu mới nhất (10 giây)
  secretStoreRef:
    name: aws-store
    kind: SecretStore
  target:
    name: db-secret                        # Tên K8s Secret đích được tạo ra tự động
  data:
  - secretKey: password                    # Key trong K8s Secret cục bộ
    remoteRef:
      key: demo/db/password                # Key thực tế trên AWS Secrets Manager
```

##### File `app-api/rollout.yaml` (Cấu hình mount volume):
```yaml
# ... trong spec.template.spec.containers.volumeMounts ...
        volumeMounts:
        - name: db-secret-volume
          mountPath: /etc/secrets          # Nơi chứa file secret bên trong container
          readOnly: true
# ... trong spec.template.spec.volumes ...
      volumes:
      - name: db-secret-volume
        secret:
          secretName: db-secret            # Mount K8s Secret được sinh ra từ ESO
```

---

### 5. Lab 2.2 · Supply Chain Security (Trivy + Cosign)

#### A. Nguyên lý hoạt động
Chúng ta bảo vệ chuỗi cung ứng phần mềm (Supply Chain) bằng 3 chốt chặn:
1.  **Quét CVE (Trivy)**: Trong pipeline CI (GitHub Actions), trước khi push ảnh lên registry, Trivy quét lỗ hổng bảo mật. Nếu phát hiện lỗ hổng mức độ `HIGH` hoặc `CRITICAL`, pipeline sẽ **dừng lại ngay lập tức** (`exit-code 1`) để ngăn việc phát hành phần mềm lỗi.
2.  **Ký ảnh (Cosign)**: Sau khi Trivy quét sạch sẽ, công cụ Cosign sử dụng khóa Private Key ký số chữ ký xác thực cho ảnh và push chữ ký này lên Registry nằm cạnh container image.
3.  **Xác minh chữ ký (Policy Controller)**: Cụm K8s chạy Sigstore Policy Controller và định nghĩa `ClusterImagePolicy` chứa khóa Public Key. Khi deploy Pod trong namespace `demo` (đã bật label `policy.sigstore.dev/include=true`), controller đối chiếu chữ ký ảnh trên registry với Public Key. Ảnh chưa ký hoặc chữ ký giả sẽ bị Admission webhook từ chối khởi tạo.

#### B. Phân tích mã nguồn cấu hình

##### File `.github/workflows/build-push.yml` (Pipeline CI):
*   **Bước quét lỗ hổng bằng Trivy**:
    ```yaml
      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME_LOWER }}:${{ steps.semver.outputs.version }}
          format: 'table'
          exit-code: '1'                  # Fail pipeline nếu có CVE nặng
          ignore-unfixed: true            # Bỏ qua các lỗi chưa có bản vá từ vendor
          vuln-type: 'os,library'
          severity: 'CRITICAL,HIGH'       # Chỉ chặn các mức độ nguy hiểm High và Critical
    ```
*   **Bước ký ảnh bằng Cosign**:
    ```yaml
      - name: Install Cosign
        uses: sigstore/cosign-installer@v3.4.0

      - name: Sign the published Docker image
        run: |
          cosign sign --yes --key <(echo "${{ secrets.COSIGN_PRIVATE_KEY }}") ${{ env.REGISTRY }}/${{ env.IMAGE_NAME_LOWER }}:${{ steps.semver.outputs.version }}
        env:
          COSIGN_PASSWORD: ${{ secrets.COSIGN_PASSWORD }} # Mật khẩu giải mã Private Key
    ```

##### File `policies/cluster-image-policy.yaml` (Cấu hình xác minh trên cụm):
```yaml
apiVersion: policy.sigstore.dev/v1beta1
kind: ClusterImagePolicy
metadata:
  name: image-signature-policy
spec:
  images:
  - glob: "ghcr.io/ptienhocse/w10-api*"    # Dải ảnh áp dụng chính sách xác minh
  authorities:
  - key:
      data: |                             # Khóa Public Key dùng để đối chiếu xác thực chữ ký số
        -----BEGIN PUBLIC KEY-----
        MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE9bShnc71iSa5ccQl/mfQKbg7tVE5
        9NEVgJRdZ5x9S5gcJzINrv+R5qLPNV2C3BUjS7PSY0lEsz/bjY//T7x4iQ==
        -----END PUBLIC KEY-----
```

---

## PHẦN E: GIẢI THÍCH CHI TIẾT CHALLENGE (MULTI-TENANT ONBOARDING)

### 1. Ý tưởng cốt lõi của Challenge
Mục tiêu của bài tập lớn này là chào đón thêm một **Team B (payments)** vào sử dụng chung cụm K8s với **Team A (demo)**, nhưng phải đảm bảo:
- **Cô lập an toàn (Isolation)**: Hai team ở hai ngăn tủ (Namespace) riêng biệt. Không team nào được can thiệp vào tài nguyên của team kia.
- **Cách ly mạng (Network Policy)**: Pod của Team B không được phép gọi trực tiếp sang dịch vụ của Team A để tránh lộ thông tin nội bộ.
- **Quản lý tài nguyên (Quota & LimitRange)**: Giới hạn ngân sách phần cứng (RAM/CPU) của Team B để không làm nghẽn cụm, đồng thời cấu hình mặc định tự động cấp limits cho Pod thiếu cấu hình.
- **Kế thừa Guardrail**: Các luật bảo mật cũ (Gatekeeper chặn root, chặn `:latest` tag, và Sigstore xác thực chữ ký ảnh) phải **tự động áp dụng** cho namespace của Team B mà không cần phải viết thêm luật hay copy-paste cấu hình mới.

---

### 2. Chi tiết cấu hình hạ tầng Tenant (`tenants/payments/`)

#### A. Khởi tạo Namespace (`tenants/payments/ns.yaml`)
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: payments
  labels:
    kubernetes.io/metadata.name: payments
    policy.sigstore.dev/include: "true"    # KÍCH HOẠT: Tự động chạy Sigstore verify image cho namespace này
```
- **Giải thích**: Ngoài việc tạo ngăn tủ tên `payments`, nhãn `policy.sigstore.dev/include: "true"` chính là chìa khóa. Nó thông báo cho webhook của Sigstore biết rằng: *"Hãy quét và xác thực chữ ký số cho mọi Pod được tạo ra tại đây"*. Đây chính là cách guardrail cũ **tự động áp dụng** cho team mới mà không cần sửa luật gốc.

#### B. Phân quyền tối giản RBAC (`tenants/payments/rbac.yaml`)
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: payments-dev-role
  namespace: payments
rules:
- apiGroups: ["", "apps", "networking.k8s.io"]
  resources: ["pods", "pods/log", "pods/exec", "services", "deployments", "replicasets", "statefulsets", "daemonsets", "ingresses"]
  verbs: ["*"]                          # Toàn quyền CRUD trên các tài nguyên workload
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: payments-dev-rolebinding
  namespace: payments
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: payments-dev-role
subjects:
- kind: User
  name: payments-dev
  apiGroup: rbac.authorization.k8s.io
```
- **Giải thích**:
  - Chúng ta sử dụng `Role` và `RoleBinding` thay vì `ClusterRoleBinding` để bó cứng quyền của `payments-dev` trong phạm vi namespace `payments`.
  - Trong phần `resources`, chúng ta liệt kê rõ ràng các tài nguyên workload chính (deployments, pods, services, ingresses) nhưng **hoàn toàn loại bỏ `secrets` và `rolebindings` / `roles`**.
  - Kết quả: `payments-dev` có thể thoải mái deploy app trong phòng của mình, nhưng không thể xem trộm mật khẩu (secret) và không thể tự leo thang đặc quyền bằng cách sửa Role hoặc RoleBinding.

#### C. Định mức tài nguyên & Mặc định Limits (`quota.yaml` & `limitrange.yaml`)
- **ResourceQuota**: Đặt ra trần tối đa.
  ```yaml
  spec:
    hard:
      requests.cpu: "200m"
      requests.memory: "128Mi"
      limits.cpu: "500m"
      limits.memory: "256Mi"
  ```
  Nếu ai đó cố tình deploy pod yêu cầu vượt quá định mức này (ví dụ: xin 512Mi RAM), API Server sẽ từ chối tạo pod đó ngay lập tức để bảo vệ tài nguyên vật lý của cụm.
- **LimitRange**: Đóng vai trò là phao cứu sinh cho Pod lười biếng.
  ```yaml
  spec:
    limits:
    - default:
        cpu: "100m"
        memory: "64Mi"
      defaultRequest:
        cpu: "50m"
        memory: "32Mi"
      type: Container
  ```
  Nếu Pod không khai báo `resources.limits` trong file YAML, bộ lọc Mutating Admission của LimitRange sẽ tự động điền các giá trị mặc định này vào Pod *trước* khi Gatekeeper kiểm duyệt. Nhờ đó, Pod đó sẽ không bị luật `require-resource-limits` của Gatekeeper chặn lại!

#### D. Cách ly mạng bằng NetworkPolicy (`tenants/payments/netpol.yaml`)
Chúng ta áp dụng 2 chính sách mạng:
1.  **Chặn Ingress (deny-all-ingress)**: Mặc định không cho phép bất kỳ dịch vụ hay namespace nào từ bên ngoài gọi trực tiếp vào các Pod trong `payments`.
2.  **Chặn Egress (allow-same-ns-egress-and-dns)**:
    - Chỉ cho phép các Pod trong `payments` gọi ra ngoài đến chính các Pod trong cùng namespace `payments` (phục vụ giao tiếp nội bộ).
    - Chỉ cho phép gửi yêu cầu truy vấn tên miền (DNS queries) cổng 53 đến namespace hệ thống `kube-system`.
    - **Kết quả**: Do không khai báo quyền truy cập đến namespace `demo`, mọi nỗ lực kết nối từ Pod của `payments` sang service `api` của `demo` đều bị chặn đứng và gây lỗi timeout.

---

### 3. GitOps và Kế thừa Guardrail qua ArgoCD

#### A. Hai ứng dụng ArgoCD mới
Chúng ta khai báo thêm 2 manifest trong `argocd/apps/` để ArgoCD quản lý GitOps:
- `payments.yaml`: Deploy toàn bộ hạ tầng (ns, rbac, quota, netpol) với sync-wave sớm `"-1"`.
- `payments-app.yaml`: Deploy ứng dụng Team B với sync-wave `"0"`.

#### B. Cơ chế tự động áp dụng chính sách bảo mật cũ
1.  **OPA Gatekeeper**:
    Tại các Constraint cũ (ví dụ: `k8sblockrootuser-constraint.yaml`), chúng ta chỉ cần thêm `- payments` vào danh sách `spec.match.namespaces`:
    ```yaml
      match:
        namespaces:
          - demo
          - payments
    ```
    Như vậy, Gatekeeper tự động quét và chặn các hành vi nguy hiểm (chạy root, tag latest, replicas > 5) trong namespace mới mà không cần viết lại bất kỳ logic Rego nào.
2.  **Sigstore Policy Controller**:
    Vì ClusterImagePolicy áp dụng ở mức toàn cụm (Cluster-scoped) cho các ảnh khớp glob `ghcr.io/ptienhocse/w10-api*`, khi namespace `payments` có nhãn `policy.sigstore.dev/include=true`, Sigstore tự động quét chữ ký số cho ảnh của Team B. Nhờ đó, ảnh đã ký hợp lệ thì chạy xanh, còn ảnh chưa ký (như `nginx:1.25`) sẽ bị chặn admission ngay lập tức.

