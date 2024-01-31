provider "aws" {
  region  = "eu-west-2"
  profile = "rokstack-github-example"
}

# Generate a unique name suffix
resource "random_pet" "name" {
  length    = 2
  separator = "-"
}

# S3 bucket for storing Docker images
resource "aws_s3_bucket" "docker_images" {
  bucket = "docker-images-${random_pet.name.id}"
  tags = {
    Name = "Docker Images Storage-${random_pet.name.id}"
  }
}

# Server-side encryption configuration for the Docker images S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "docker_images_encryption" {
  bucket = aws_s3_bucket.docker_images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket to store ssh keys with a unique name
resource "aws_s3_bucket" "my_ssh_keys" {
  bucket = "my-ssh-keys-${random_pet.name.id}"
  tags = {
    Name = "SSH Keys Storage-${random_pet.name.id}"
  }
}

# Server-side encryption configuration for the S3 bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "my_ssh_keys_encryption" {
  bucket = aws_s3_bucket.my_ssh_keys.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Upload the SSH private key to the S3 bucket
resource "aws_s3_object" "private_key" {
  bucket                 = aws_s3_bucket.my_ssh_keys.bucket
  key                    = "mykey"
  source                 = "${path.module}/mykey"
  server_side_encryption = "AES256"
}

# Create an AWS key pair using the public key
resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key-${random_pet.name.id}"
  public_key = file("${path.module}/mykey.pub")
}

# Create a security group that allows SSH and HTTP access
resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh-${random_pet.name.id}"
  description = "Allow SSH and HTTP inbound traffic"

  # Existing rule: Allow SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # New rule: Allow HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # New rule: Allow custom port (e.g., 8080 for your application)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

   # New rule: Allow HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}

# Create policy to access the S3 bucket
resource "aws_iam_policy" "docker_upload_policy" {
  name        = "DockerUploadPolicy-${random_pet.name.id}"
  path        = "/"
  description = "Policy for uploading Docker images to S3"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          "${aws_s3_bucket.docker_images.arn}",
          "${aws_s3_bucket.docker_images.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "ci_cd_role" {
  name = "CI_CD_Role-${random_pet.name.id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = ["ec2.amazonaws.com"] # Change this to the service that runs your CI/CD jobs, e.g., "ecs-tasks.amazonaws.com" for ECS tasks
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "docker_upload_policy_attachment" {
  role       = aws_iam_role.ci_cd_role.name
  policy_arn = aws_iam_policy.docker_upload_policy.arn
}

# Launch an EC2 instance with the key pair and associate it with the security group + Install Docker
resource "aws_instance" "example" {
  ami           = "ami-09d6bbc1af02c2ca1" # Amazon Linux 2023 AMI for x86_64
  instance_type = "t3.micro" # or any other suitable instance type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  # Adjusted user data script for Amazon Linux 2023
  user_data = <<-EOF
              #!/bin/bash
              sudo dnf update -y
              sudo dnf install docker -y
              sudo systemctl start docker
              sudo systemctl enable docker
              sudo usermod -aG docker ec2-user
              EOF

  tags = {
    Name = "rokstack-react-github-${random_pet.name.id}"
  }
}
# Associate an Elastic IP with the EC2 instanc
resource "aws_eip" "example" {
  instance = aws_instance.example.id
}

# Create an IAM user for CI/CD operations
resource "aws_iam_user" "ci_cd_user" {
  name = "ci-cd-user-${random_pet.name.id}"
}

#Generate access keys for the IAM user
resource "aws_iam_access_key" "ci_cd_user_key" {
  user = aws_iam_user.ci_cd_user.name
}

# Attach the policy to the IAM user to grant access to the S3 bucket
resource "aws_iam_user_policy_attachment" "ci_cd_user_policy_attachment" {
  user       = aws_iam_user.ci_cd_user.name
  policy_arn = aws_iam_policy.docker_upload_policy.arn
}

resource "aws_s3_bucket" "ci_cd_secrets" {
  bucket = "ci-cd-secrets-${random_pet.name.id}"

  tags = {
    Name = "CI/CD Secrets Storage - ${random_pet.name.id}"
  }
}

resource "aws_s3_object" "ci_cd_user_access_key_id_object" {
  bucket       = aws_s3_bucket.ci_cd_secrets.id
  key          = "ci_cd_user_access_key_id"
  content      = aws_iam_access_key.ci_cd_user_key.id
  acl          = "private"
}

resource "aws_s3_object" "ci_cd_user_secret_access_key_object" {
  bucket       = aws_s3_bucket.ci_cd_secrets.id
  key          = "ci_cd_user_secret_access_key"
  content      = aws_iam_access_key.ci_cd_user_key.secret
  acl          = "private"
}

output "ci_cd_secrets_bucket_name" {
  value = aws_s3_bucket.ci_cd_secrets.bucket
  description = "The name of the S3 bucket where CI/CD secrets are stored."
}

output "docker_s3_bucket_name" {
  value = aws_s3_bucket.docker_images.bucket
  description = "The name of the S3 bucket used to store Docker images"
}

# Output the public IP of the EC2 instance
output "public_ip" {
  value = aws_eip.example.public_ip
}

output "ci_cd_role_arn" {
  value = aws_iam_role.ci_cd_role.arn
  description = "The ARN of the IAM role for CI/CD to assume"
}