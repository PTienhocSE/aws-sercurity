# W10 - Progressive Delivery with Analysis

GitOps setup for API deployment với Argo Rollouts + AnalysisTemplate.

## Concept

Deploy API với **canary strategy** và **automated analysis**:
- Rollout: 10% → 50% → 100%
- AnalysisTemplate query Prometheus để check success rate ≥ 95%
- Auto rollback nếu analysis fail
- AlertManager gửi email khi có SLO violation

## Requirements

- Docker Desktop
- kubectl
- minikube
- git

## Structure

```
w10/
├── app-api/              # API Rollout manifests
│   ├── rollout.yaml      # Argo Rollout với canary strategy
│   ├── service.yaml      # Service expose API
│   └── servicemonitor.yaml # Prometheus metrics scraper
├── app-analysis/         # Analysis manifests
│   └── analysis-template.yaml # Template phân tích success rate
├── app-alert/            # Alert manifests
│   ├── prometheus-rules.yaml # PrometheusRule cho SLO alerts
│   ├── email-secret.yaml # Gmail password (NOT COMMITTED)
│   └── README.md         # Alert setup guide
├── app-common/           # Common resources
│   └── demo-namespace.yaml # Namespace demo
├── src/                  # Source code
│   └── api/              # Flask API application
├── argocd/
│   ├── apps/             # ArgoCD Application manifests
│   │   ├── app-api.yaml  # Deploy API Rollout
│   │   ├── app-analysis.yaml # Deploy AnalysisTemplate
│   │   ├── app-alert.yaml # Deploy PrometheusRule
│   │   ├── app-common.yaml # Deploy common resources
│   │   ├── k8s-prometheus.yaml # Prometheus + AlertManager
│   │   └── k8s-rollout.yaml # Argo Rollouts controller
│   └── root.yaml         # App of Apps pattern
└── README.md
```

## Quick Start

### 1. Setup Cluster
```bash
minikube start -p w10 --driver=docker
kubectl config use-context w10
```

### 2. Install ArgoCD
```bash
kubectl create ns argocd
kubectl apply --server-side -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server
```

### 3. Access ArgoCD UI
```bash
# Port forward
kubectl -n argocd port-forward svc/argocd-server 8080:443 &

# Get password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

### 4. Deploy App of Apps
```bash
kubectl apply -f argocd/root.yaml
```

### 5. Setup Email Alert (Optional)
```bash
# Follow instructions in app-alert/README.md
cp app-alert/email-secret.yaml.example app-alert/email-secret.yaml
kubectl apply -f app-alert/email-secret.yaml
```

## Components

### Core
- **Argo Rollouts**: Progressive delivery controller
- **Prometheus Stack**: Metrics collection + AlertManager
- **API**: Flask application với metrics endpoint

### GitOps Applications
- `app-api`: API Rollout với canary strategy
- `app-analysis`: AnalysisTemplate cho automated validation
- `app-alert`: PrometheusRule cho runtime alerting
- `app-common`: Shared resources (namespace)
- `k8s-prometheus`: Monitoring stack
- `k8s-rollout`: Argo Rollouts controller

## Verify Deployment

### Check Rollout Status
```bash
# Watch rollout progress
kubectl get rollout api -n demo -w

# Check current state
kubectl get rollout api -n demo

# Check pods
kubectl get pods -n demo -l app=api
```

### Check AnalysisRun
```bash
# List analysis runs
kubectl get analysisrun -n demo

# Watch latest analysis
kubectl get analysisrun -n demo --sort-by=.metadata.creationTimestamp | tail -1

# Describe for detailed metrics
kubectl describe analysisrun -n demo <name>
```

### Query Prometheus Metrics
```bash
# Success rate metric
kubectl run test-query --image=curlimages/curl:latest --rm -i --restart=Never -n monitoring -- \
  curl -s 'http://kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/query?query=api:success_rate:5m'
```

## Test Scenarios (GitOps)

### Test 1: Successful Deployment (Success Rate ≥ 90%)
```bash
# Edit rollout to deploy with no errors
nano app-api/rollout.yaml
# Set: ERROR_RATE: "0"

git add app-api/rollout.yaml
git commit -m "test: deploy with 0% error rate"
git push origin main

# Watch AnalysisRun succeed
kubectl get analysisrun -n demo -w
```

### Test 2: Failed Deployment (Success Rate < 90%)
```bash
# Edit rollout to deploy with 15% error rate
nano app-api/rollout.yaml
# Set: ERROR_RATE: "0.15"

git add app-api/rollout.yaml
git commit -m "test: deploy with 15% error rate (should fail)"
git push origin main

# Watch AnalysisRun fail and auto rollback
kubectl get analysisrun -n demo -w
kubectl get rollout api -n demo
```

### Test 3: Trigger SLO Alert Email
```bash
# Edit rollout to set 10% error rate (triggers alert, but passes canary)
nano app-api/rollout.yaml
# Set: ERROR_RATE: "0.10"

git add app-api/rollout.yaml
git commit -m "test: deploy with 10% error rate (90% success)"
git push origin main

# Canary passes (≥90%) but SLO alert fires (below 95%)
# Wait 2-3 minutes, then check email inbox
```


## Configuration Reference

### Sync Waves
ArgoCD applications deploy in order:
- Wave -1: `app-common` (namespace)
- Wave 0: `k8s-prometheus`, `k8s-rollout` (infrastructure)
- Wave 1: `app-analysis`, `app-alert` (configuration)
- Wave 2: `app-api` (application)

## Cleanup

```bash
# Delete ArgoCD applications
kubectl delete -f argocd/root.yaml

# Wait for resources to be cleaned up
kubectl get all -n demo
kubectl get all -n monitoring

# Delete ArgoCD
kubectl delete ns argocd

# Stop minikube
minikube stop -p w10
minikube delete -p w10
```

## Multi-Tenant Challenge: Onboard Team Payments (Cô lập an toàn)

### 1. Vì sao các guardrail bảo mật cũ tự động áp dụng cho namespace/team mới (`payments`) mà không cần viết lại luật mới?

- **Sigstore Policy-Controller (Supply Chain)**: ClusterImagePolicy (`image-signature-policy`) được cấu hình ở mức Cluster. Webhook của Sigstore được thiết lập để tự động kiểm duyệt tất cả các namespace có gắn label `policy.sigstore.dev/include=true`. Khi onboard team `payments`, chúng ta chỉ cần gắn label này vào namespace `payments` trong file [ns.yaml](file:///D:/Workspace/Study/AWS/aws-sercurity/tenants/payments/ns.yaml). Hệ thống sẽ tự động bắt đầu quét chữ ký số cho mọi Pod triển khai trong namespace này mà không cần sửa đổi hay viết thêm bất kỳ chính sách (ClusterImagePolicy) nào.
- **OPA Gatekeeper (Admission Control)**: Các Constraint (luật chặn) như chặn user root, chặn tag `:latest`, bắt buộc cấu hình CPU/memory limits,... được cấu hình áp dụng cho namespace `payments` bằng cách mở rộng danh sách `spec.match.namespaces` của các Constraint sẵn có trong thư mục `gatekeeper/constraints/` để bao gồm cả `payments`. Do đó, chúng ta kế thừa toàn bộ các Template logic cũ và chỉ cần cấu hình phạm vi áp dụng, giúp giữ nguyên mã nguồn luật cũ.

### 2. Sự khác biệt giữa Role / RoleBinding và ClusterRole / ClusterRoleBinding trong việc giữ cô lập (isolation)?

- **Role & RoleBinding (Namespace-scoped)**:
  - **Role** định nghĩa các quyền (verbs trên các resources) giới hạn trong phạm vi một namespace cụ thể.
  - **RoleBinding** liên kết Role đó với một User/ServiceAccount trong chính namespace đó.
  - **Ý nghĩa cô lập**: User `payments-dev` được gán quyền thông qua Role và RoleBinding trong namespace `payments` sẽ **chỉ** có quyền thực thi thao tác trong phạm vi `payments`. Họ hoàn toàn không thể xem, sửa đổi hoặc can thiệp vào tài nguyên của namespace `demo` hay các namespace khác.
- **ClusterRole & ClusterRoleBinding (Cluster-scoped)**:
  - **ClusterRole** định nghĩa các quyền trên toàn bộ cụm Kubernetes (cho cả tài nguyên non-namespaced như Nodes, Namespaces và tài nguyên namespaced ở mọi namespace).
  - **ClusterRoleBinding** áp dụng ClusterRole đó cho User/ServiceAccount trên **toàn cụm** (băng qua tất cả các namespace).
  - **Nguy cơ bảo mật**: Nếu sử dụng `ClusterRoleBinding` cho `payments-dev`, họ sẽ có quyền truy cập sang namespace `demo` (hoặc các namespace hệ thống như `kube-system`, `argocd`), phá vỡ tính cô lập đa người dùng (multi-tenant isolation) của platform.

