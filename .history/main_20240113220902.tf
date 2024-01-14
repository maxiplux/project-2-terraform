terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}


resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

resource "aws_key_pair" "generated_key" {
  key_name   = "terraform-pem-ha"
  public_key = tls_private_key.ssh.public_key_openssh


}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "terraform-ha.pem"
  file_permission = "0600"
}



# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "terraform_vpc" {
  cidr_block           = "172.16.0.0/16"
  enable_dns_hostnames = "true"

  tags = {
    Name = "Terraform-ha"
  }
}
resource "aws_internet_gateway" "terraform_vpc_internet_gateway" {
  vpc_id = aws_vpc.terraform_vpc.id
  tags = {
    Name = "Terraform-ha"
  }
}
resource "aws_route_table" "terraform_aws_route_table" {
  vpc_id = aws_vpc.terraform_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.terraform_vpc_internet_gateway.id
  }
}



resource "aws_subnet" "terraform_subnet-1a" {
  vpc_id                  = aws_vpc.terraform_vpc.id
  cidr_block              = "172.16.10.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Terraform-ha"
  }
}

resource "aws_subnet" "terraform_subnet-1b" {
  vpc_id                  = aws_vpc.terraform_vpc.id
  cidr_block              = "172.16.11.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "Terraform-ha"
  }
}

resource "aws_eip" "terraform_eip" {
  vpc = true
  tags = {
    Name = "Terraform-ha"
  }
}
resource "aws_nat_gateway" "terraform_aws_nat_gateway" {
  allocation_id = aws_eip.terraform_eip.id
  subnet_id     = aws_subnet.terraform_subnet-1a.id
  tags = {
    Name = "Terraform-ha"
  }
  depends_on = [aws_internet_gateway.terraform_vpc_internet_gateway]

}



resource "aws_route_table_association" "terraform_aws_route_table_association" {
  subnet_id      = aws_subnet.terraform_subnet-1a.id
  route_table_id = aws_route_table.terraform_aws_route_table.id
}

resource "aws_network_interface" "terraform_network_interface" {
  subnet_id   = aws_subnet.terraform_subnet-1a.id
  private_ips = ["172.16.10.100"]

  tags = {
    Name = "Terraform-ha",
  }
}

# ------------------------------------------------------
# Define un grupo de seguridad con acceso al puerto 8080
# ------------------------------------------------------
resource "aws_security_group" "terraform_security_group" {
  name   = "terraform_security_group-sg"
  vpc_id = aws_vpc.terraform_vpc.id
  ingress {
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description      = "HTTP access"
    from_port        = 80
    to_port          = 80
    protocol         = "TCP"
  }



  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Terraform-ha",
  }
}



resource "aws_security_group" "terraform_security_icmp_group" {
  name   = "terraform_security_group-icmp-sg"
  vpc_id = aws_vpc.terraform_vpc.id
  ingress {
    //cidr_blocks = ["0.0.0.0/0"]
    description = "Acceso al puerto ICMP desde el exterior"

    from_port        = -1
    to_port          = -1
    protocol         = "icmp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name = "Terraform-ha",
  }
}

resource "aws_security_group" "terraform_security_ssh_group" {
  name   = "terraform_security_ssh_group-sg"
  vpc_id = aws_vpc.terraform_vpc.id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "Acceso al puerto 22 desde el exterior"
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
  }

  tags = {
    Name = "Terraform-ha",
  }
}
provider "tls" {}





resource "aws_instance" "terraform_instance_first" {
  ami      = "ami-053b0d53c279acc90"
  key_name = aws_key_pair.generated_key.key_name

  instance_type = "t2.micro"
  subnet_id     = aws_subnet.terraform_subnet-1a.id


  vpc_security_group_ids = [aws_security_group.terraform_security_icmp_group.id, aws_security_group.terraform_security_group.id, aws_security_group.terraform_security_ssh_group.id]
  tags = {
    Name = "terraform_instance_first",
  }
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt-get install ec2-instance-connect -y
              sudo apt install apache2 -y
              sudo systemctl status sshd
              sudo systemctl start apache2

              sudo bash -c 'echo your very terraform_instance_first web server 111111 > /var/www/html/index.html'
              EOF
}

resource "aws_instance" "terraform_instance_second" {
  ami      = "ami-053b0d53c279acc90"
  key_name = aws_key_pair.generated_key.key_name

  instance_type = "t2.micro"
  subnet_id     = aws_subnet.terraform_subnet-1a.id


  vpc_security_group_ids = [aws_security_group.terraform_security_icmp_group.id, aws_security_group.terraform_security_group.id, aws_security_group.terraform_security_ssh_group.id]
  tags = {
    Name = "terraform_instance_first",
  }
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt-get install ec2-instance-connect -y
              sudo apt install apache2 -y
              sudo systemctl status sshd
              sudo systemctl start apache2

              sudo bash -c 'echo your very terraform_instance_second web server 22222222222 > /var/www/html/index.html'
              EOF
}



# ----------------------------------------
# Load Balancer público con dos instancias
# ----------------------------------------
resource "aws_lb" "terraform-alb" {
  load_balancer_type = "application"
  name               = "terraform-alb"
  security_groups    = [aws_security_group.terraform_security_group.id]
  subnets            = [aws_subnet.terraform_subnet-1a.id, aws_subnet.terraform_subnet-1b.id]
}


# ----------------------------------
# Target Group para el Load Balancer
# ----------------------------------
resource "aws_lb_target_group" "terraform_aws_lb_target_group" {
  name     = "terraformawslbtargetgroup"
  port     = 80
  vpc_id   = aws_vpc.terraform_vpc.id
  protocol = "HTTP"

  health_check {
    enabled  = true
    matcher  = "200"
    path     = "/"
    port     = "8080"
    protocol = "HTTP"
  }
}

# -----------------------------
# Attachment para el servidor 1
# -----------------------------
resource "aws_lb_target_group_attachment" "terraform_alb_target_group_1" {
  target_group_arn = aws_lb_target_group.terraform_aws_lb_target_group.arn
  target_id        = aws_instance.terraform_instance_first.id
  port             = 80
}

# -----------------------------
# Attachment para el servidor 2
# -----------------------------
resource "aws_lb_target_group_attachment" "terraform_alb_target_group_2" {
  target_group_arn = aws_lb_target_group.terraform_aws_lb_target_group.arn
  target_id        = aws_instance.terraform_instance_second.id
  port             = 80
}

# ------------------------
# Listener para nuestro LB
# ------------------------
resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.terraform-alb.arn
  port              = 80

  default_action {
    target_group_arn = aws_lb_target_group.terraform_aws_lb_target_group.arn
    type             = "forward"
  }
}


output "dns_load_balancer" {
  description = "DNS ALB"
  value       = "http://${aws_lb.terraform-alb.dns_name}"
}


output "server_public_dns_firts" {
  value = "http://${aws_instance.terraform_instance_first.public_dns}"
}
output "server_public_dns_second" {
  value ="http://${aws_instance.terraform_instance_second.public_dns}"
}



//terraform output -raw private_key > terraform.pem
output "private_key" {
  value     = tls_private_key.ssh.private_key_pem
  sensitive = true
}
