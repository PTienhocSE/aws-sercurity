variable "aws_region" {
  type        = string
  description = "AWS Region to deploy the resources"
  default     = "ap-southeast-1"
}

variable "instance_type" {
  type        = string
  description = "EC2 Instance type (Recommend t3.medium or t3.large)"
  default     = "t3.medium"
}

variable "key_name" {
  type        = string
  description = "Name of the existing EC2 Key Pair in your AWS account"
}

variable "my_ip" {
  type        = string
  description = "Your local public IP (CIDR format) to restrict SSH access. Set to 0.0.0.0/0 to allow all."
  default     = "0.0.0.0/0"
}

variable "volume_size" {
  type        = number
  description = "Root disk volume size in GB"
  default     = 20
}
