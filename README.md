## General overview of this settings.
### Providers Configuration

-   **AWS Provider**: Configures the AWS provider to interact with AWS services.
-   **TLS Provider**: Used for generating a TLS private key for SSH access.

### Resource: TLS Private Key

-   Generates an RSA private key for SSH access.

### Resource: AWS Key Pair

-   Creates an AWS key pair using the generated RSA public key.

### Resource: Local File

-   Stores the generated private key locally with secure file permissions.

### AWS Network Configuration

-   **AWS VPC (Virtual Private Cloud)**: Creates a VPC with a specified CIDR block.
-   **Internet Gateway**: Attaches an internet gateway to the VPC for internet access.
-   **Route Table & Association**: Sets up a route table for the VPC, directing traffic to the internet gateway.
-   **Subnets**: Creates two subnets in different availability zones for high availability.
-   **Elastic IP & NAT Gateway**: Configures an Elastic IP and a NAT Gateway for outbound internet access from instances in the private subnet.
-   **Network Interface**: Creates a network interface with a specific private IP.

### Security Groups

-   **General Security Group**: Allows HTTP access (port 80) and general outbound traffic.
-   **ICMP Security Group**: Configures ICMP access for ping operations.
-   **SSH Security Group**: Allows SSH access (port 22).

### AWS EC2 Instances

-   **Two EC2 Instances**: Launches two instances with specified AMIs, instance types, and user data scripts for initial setup. These instances are placed in one of the subnets and associated with the created security groups.

### Load Balancer & Target Group

-   **Application Load Balancer (ALB)**: Sets up a load balancer across the subnets.
-   **Target Group & Attachments**: Creates a target group for the load balancer and attaches the EC2 instances to it.
-   **Load Balancer Listener**: Configures a listener for the ALB to forward traffic to the target group.

### Outputs

-   **DNS of Load Balancer & EC2 Instances**: Outputs the DNS names of the load balancer and the EC2 instances.
-   **Private Key**: Outputs the generated private key (sensitive information).

### Usage

The script is a comprehensive setup for deploying a load-balanced, high-availability application in AWS. The instances are configured with Apache and can be accessed through the load balancer. The security groups ensure controlled access to the instances.

### How to execute this project.
-   setup your AWS CLI and terraform will read your settings to target this infraestructure
-   Run `terraform init` to initialize Terraform and download the required providers.
-   Run `terraform plan` to see the execution plan.
-   Run `terraform apply` to apply the configuration and create the resources in AWS.
