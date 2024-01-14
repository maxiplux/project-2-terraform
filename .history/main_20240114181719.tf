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
  default_tags {
    tags = {
      Name    = "weclouddata"
      project = "devops"
    }
  }
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

########################################################################################

resource "aws_security_group" "postgres" {
  vpc_id      = aws_vpc.terraform_vpc.id
  name        = "uddin"
  description = "Allow all inbound for Postgres"
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_db_instance" "postgres" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "postgres"
  db_subnet_group_name = aws_db_subnet_group.postgres.name

  engine_version         = "15"          # Specify the PostgreSQL version
  instance_class         = "db.m5.large" # Choose the instance class based on your requirement
  username               = "postgres"
  password               = "postgres"
  parameter_group_name   = "default.postgres15"
  vpc_security_group_ids = [aws_security_group.postgres.id]

  skip_final_snapshot = true
  publicly_accessible = true

  tags = {
    Name = "MyDBInstance"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "main"
  subnet_ids = [aws_subnet.terraform_subnet-1a.id, aws_subnet.terraform_subnet-1b.id]

  tags = {
    Name = "My DB subnet group"
  }
}

####################################################################################################











resource "aws_launch_configuration" "weclouddata" {
  name_prefix   = "base_aws_launch_configuration-config"
  image_id      = "ami-0c7217cdde317cfec"
  instance_type = "t2.micro"


  user_data       = <<-EOF
                    #!/bin/bash
                    echo "export DB_HOST=${aws_db_instance.postgres.address}" >> /etc/environment
                    sudo apt update -y
                    sudo apt-get install ec2-instance-connect -y
                    sudo add-apt-repository -y ppa:deadsnakes/ppa
                    sudo apt install -y python3.12

                    sudo apt-get install -y  ca-certificates curl gnupg mc pip
                    sudo install -m 0755 -d /etc/apt/keyrings
                    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                    sudo chmod a+r /etc/apt/keyrings/docker.gpg

                    # Add the repository to Apt sources:
                    echo \
                    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
                    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
                    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                    sudo apt-get update -y
                    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

                    sudo mkdir /app
                    sudo chown ubuntu:users /app
                    cd /app && git clone https://github.com/maxiplux/api-python-project-devops-fast-api.git
                    cd api-python-project-devops-fast-api && pip install -r requirements.txt && sudo uvicorn main:app --reload --host 0.0.0.0 --port 80
              EOF
  key_name        = aws_key_pair.generated_key.key_name
  security_groups = [aws_security_group.terraform_security_group.id, aws_security_group.terraform_security_ssh_group.id, aws_security_group.terraform_security_icmp_group.id]


  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_autoscaling_group" "weclouddata" {
  min_size             = 2
  max_size             = 6
  desired_capacity     = 2
  launch_configuration = aws_launch_configuration.weclouddata.name
  vpc_zone_identifier  = [aws_subnet.terraform_subnet-1a.id, aws_subnet.terraform_subnet-1b.id]
}

resource "aws_lb" "weclouddata" {
  name               = "weclouddata-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.terraform_security_group.id]
  subnets            = [aws_subnet.terraform_subnet-1a.id, aws_subnet.terraform_subnet-1b.id]
}

resource "aws_lb_listener" "weclouddata" {
  load_balancer_arn = aws_lb.weclouddata.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.weclouddata.arn
  }
}

resource "aws_lb_target_group" "weclouddata" {
  name     = "weclouddata"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.terraform_vpc.id
}


resource "aws_autoscaling_attachment" "weclouddata" {
  autoscaling_group_name = aws_autoscaling_group.weclouddata.id
  alb_target_group_arn   = aws_lb_target_group.weclouddata.arn
}



output "dns_load_balancer" {
  description = "DNS ALB"
  value       = "http://${aws_lb.weclouddata.dns_name}"
}




output "db_address" {
  value = aws_db_instance.postgres.address
}


//terraform output -raw private_key > terraform.pem
output "private_key" {
  value     = tls_private_key.ssh.private_key_pem
  sensitive = true
}


