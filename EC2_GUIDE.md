# Hướng dẫn chạy Lab trên AWS EC2 bằng Terraform

Tài liệu này hướng dẫn từng bước để tự động tạo một máy ảo EC2 trên AWS bằng Terraform, sau đó cài đặt Kubernetes (Kind) + ArgoCD để chạy dự án này, và cuối cùng là cách hủy tài nguyên (destroy) dễ dàng.

---

## Bước 1: Khởi tạo tài nguyên bằng Terraform

### 1. Chuẩn bị thông tin cấu hình
Vào thư mục `terraform/` trong dự án của bạn và tạo một file đặt tên là `terraform.tfvars` để khai báo tên Key Pair của bạn (key đã tạo sẵn trên AWS EC2):

```hcl
# terraform/terraform.tfvars
key_name      = "ten-key-pair-cua-ban"       # Bắt buộc (Tên Key Pair của bạn trên AWS)
aws_region    = "ap-southeast-1"             # (Tùy chọn) Default: Singapore (ap-southeast-1)
instance_type = "t3.medium"                  # (Tùy chọn) Khuyến nghị t3.medium hoặc t3.large
volume_size   = 20                           # (Tùy chọn) Ổ cứng 20GB gp3
```

### 2. Chạy lệnh Terraform để Deploy
Mở terminal ở máy cục bộ của bạn, chuyển hướng vào thư mục `terraform/` và chạy:

```bash
# Di chuyển vào folder terraform
cd terraform

# 1. Khởi tạo Terraform provider
terraform init

# 2. Xem trước các tài nguyên sẽ được tạo
terraform plan

# 3. Tạo tài nguyên trên AWS (nhập 'yes' khi được hỏi)
terraform apply
```

Sau khi hoàn tất, Terraform sẽ hiển thị kết quả output tương tự như:
- **`instance_public_ip`**: Địa chỉ IP công cộng của EC2.
- **`ssh_command`**: Câu lệnh SSH để kết nối đến EC2.
- **`argocd_url`**: Địa chỉ truy cập ArgoCD Web UI (`https://<EC2-PUBLIC-IP>:8443`).

---

## Bước 2: Kết nối SSH vào EC2 và Chạy Script Cấu Hình

Copy câu lệnh SSH từ output của Terraform, trỏ đường dẫn đến file khóa `.pem` cục bộ của bạn và chạy:

```bash
# Ví dụ kết nối:
ssh -i "path/to/your-key.pem" ubuntu@<EC2-PUBLIC-IP>
```

Sau khi đã vào terminal của EC2, clone repo bảo mật này về và chạy script cài đặt tự động:

```bash
# 1. Clone repository bảo mật của bạn trên EC2
git clone https://github.com/PTienhocSE/security-aws.git
cd security-aws

# 2. Cấp quyền thực thi và chạy script setup
chmod +x scripts/setup-ec2.sh
./scripts/setup-ec2.sh
```

---

## Bước 3: Đăng nhập ArgoCD & Đồng bộ Platform

1. Khi script hoàn tất, nó sẽ in ra mật khẩu ArgoCD admin:
   - **URL**: `https://<EC2-PUBLIC-IP>:8443`
   - **Username**: `admin`
   - **Password**: `<MẬT_KHẨU_TỰ_ĐỘNG_TẠO>`

2. Mở trình duyệt Web, truy cập vào URL trên (bỏ qua cảnh báo SSL tự ký).
3. Đăng nhập bằng tài khoản `admin` và mật khẩu được in ra.
4. Triển khai ứng dụng Root (App of Apps) để kéo toàn bộ Lab về tự động:
   ```bash
   # Chạy trên EC2:
   kubectl apply -f argocd/root.yaml
   ```

ArgoCD sẽ tự động tải các ứng dụng con như `rbac`, `gatekeeper`, `gatekeeper-policies` và `api` lên cluster!

---

## Bước 4: Hủy tài nguyên (Destroy)

Khi hoàn thành bài Lab và muốn dọn dẹp tài nguyên để tránh phát sinh chi phí trên AWS, bạn chỉ cần quay lại thư mục `terraform/` ở máy cục bộ và chạy lệnh duy nhất:

```bash
# Từ máy cục bộ, trong thư mục terraform/
terraform destroy
```
Nhập `yes` để xác nhận hủy toàn bộ VPC, Subnet, Security Group và EC2 instance.
