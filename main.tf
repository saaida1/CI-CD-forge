provider "aws" {
  region = "us-east-1"
}

resource "aws_security_group" "allow_trafic" {
  name        = "allow_trafic"
  description = "Allow SSH and HTTP traffic"


  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "jenkins" {
  ami             = "ami-073c5fc1798eb7056"
  instance_type   = "t2.micro"
  key_name        = "Terraform"
  security_groups = [aws_security_group.allow_trafic.name]

  user_data = templatefile("${path.module}/user_data.sh", {
    docker_username = var.docker_username
    docker_token    = var.docker_token
    git_username    = var.git_username
    git_token       = var.git_token
  })

  tags = {
    Name = "JenkinsSetUp-${var.user_id}"
  }
}

output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}
