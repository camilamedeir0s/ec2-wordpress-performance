# Define o provedor AWS
provider "aws" {
  region = "us-east-1"  # Ajuste conforme a sua região
}

# Criação de uma VPC
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
}

# Criação de uma sub-rede pública para o NAT Gateway (se necessário)
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

# Criação de uma sub-rede privada para as instâncias EC2 e Load Balancer
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
}

# Criação de um NAT Gateway para dar acesso à internet para a sub-rede privada
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id
}

# Tabela de rotas para a sub-rede privada, usando o NAT Gateway
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main_vpc.id
}

resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}

# Associação da tabela de rotas com a sub-rede privada
resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Criação de um Security Group para instâncias privadas e Load Balancer interno
resource "aws_security_group" "private_sg" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # Acesso HTTP dentro da VPC
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # Acesso SSH dentro da VPC
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Criação das instâncias EC2 para WordPress
resource "aws_instance" "wordpress_instance1" {
  ami           = "ami-0862be96e41dcbf74"  # Substitua com a AMI do Ubuntu mais recente
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_subnet.id
  security_groups = [aws_security_group.private_sg.name]

  tags = {
    Name = "WordPressInstance1"
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              EOF
}

resource "aws_instance" "wordpress_instance2" {
  ami           = "ami-0862be96e41dcbf74"  # Substitua com a AMI do Ubuntu mais recente
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_subnet.id
  security_groups = [aws_security_group.private_sg.name]

  tags = {
    Name = "WordPressInstance2"
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              EOF
}

# Criação de uma instância EC2 para o banco de dados MySQL
resource "aws_instance" "mysql_instance" {
  ami           = "ami-0862be96e41dcbf74"  # Substitua com a AMI do Ubuntu mais recente
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_subnet.id
  security_groups = [aws_security_group.private_sg.name]

  tags = {
    Name = "MySQLInstance"
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y docker.io
              sudo systemctl start docker
              sudo systemctl enable docker
              EOF
}

# Criação da instância EC2 para rodar o Locust
resource "aws_instance" "locust_instance" {
  ami           = "ami-0862be96e41dcbf74"  # Substitua com a AMI do Ubuntu mais recente
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private_subnet.id
  security_groups = [aws_security_group.private_sg.name]

  tags = {
    Name = "LocustInstance"
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y python3-pip
              sudo apt install python3-locust -y
              EOF
}

# Criação do Load Balancer interno
resource "aws_lb" "wordpress_lb" {
  name               = "wordpress-lb"
  internal           = true  # Tornar o Load Balancer interno
  load_balancer_type = "application"
  security_groups    = [aws_security_group.private_sg.id]
  subnets            = [aws_subnet.private_subnet.id]
}

# Criação de um target group para as instâncias WordPress
resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main_vpc.id
}

# Adicionar as instâncias WordPress ao target group
resource "aws_lb_target_group_attachment" "wordpress_instance1_tg_attachment" {
  target_group_arn = aws_lb_target_group.wordpress_tg.arn
  target_id        = aws_instance.wordpress_instance1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "wordpress_instance2_tg_attachment" {
  target_group_arn = aws_lb_target_group.wordpress_tg.arn
  target_id        = aws_instance.wordpress_instance2.id
  port             = 80
}

# Criação de um listener no Load Balancer para a porta 80
resource "aws_lb_listener" "wordpress_listener" {
  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

# Output com o endereço DNS do Load Balancer
output "load_balancer_dns" {
  value = aws_lb.wordpress_lb.dns_name
}
