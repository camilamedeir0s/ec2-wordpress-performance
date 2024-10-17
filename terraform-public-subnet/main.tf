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

# Criação de um Internet Gateway e associação à VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
}

# Criação de uma sub-rede pública para a instância EC2
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

# Criação da segunda sub-rede pública em us-east-1b
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

# Tabela de rotas para a sub-rede pública, usando o Internet Gateway
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

# Associação da tabela de rotas com a sub-rede pública
resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Criação de um Security Group restritivo
resource "aws_security_group" "public_sg" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = [aws_vpc.main_vpc.cidr_block]
  }

  # Permite todo o tráfego de saída (egress) para a internet (para download de pacotes)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Criação da policy para acesso ao S3
resource "aws_iam_policy" "s3_access_policy" {
  name        = "EC2S3AccessPolicy"
  description = "Permite acesso ao S3"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = [
        "s3:GetObject",
        "s3:ListBucket",
        "s3:PutObject"
      ],
      Resource = "*"
    }]
  })
}

# Criação de uma role associada à EC2 com permissões de acesso ao S3
resource "aws_iam_role" "ec2_role" {
  name = "ec2Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# Associando a policy de S3 à role da EC2
resource "aws_iam_role_policy_attachment" "attach_s3_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

# Criação do perfil de instância (Instance Profile) para a EC2 associada à role
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2InstanceProfile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "mysql_instance" {
  ami           = "ami-0866a3c8686eaeeba"  # Substitua com a AMI do Ubuntu mais recente
  instance_type = "t3.small"
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  iam_instance_profile    = aws_iam_instance_profile.ec2_instance_profile.name

  tags = {
    Name = "MySqlInstance"
  }

  depends_on = [
    aws_lb.wordpress_lb
  ]

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y docker.io
              sudo systemctl start docker
              sudo systemctl enable docker
              sudo docker run -p 3306:3306 --name wordpressdb -e MYSQL_ROOT_PASSWORD=rootpassword -e MYSQL_DATABASE=wordpress -e MYSQL_USER=wpuser -e MYSQL_PASSWORD=password -d mysql:5.7

              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              sudo apt install unzip
              unzip awscliv2.zip
              sudo ./aws/install

              aws s3 cp s3://nuvem-wp-bkp/bkp.sql ./bkp.sql
              sudo docker cp ./bkp.sql wordpressdb:/bkp.sql
              sudo docker exec -i wordpressdb mysql -u root -p'rootpassword' wordpress < ./bkp.sql
              sudo docker exec -i wordpressdb mysql -u wpuser -p'password' wordpress -e "UPDATE wp_options SET option_value = 'http://${aws_lb.wordpress_lb.dns_name}' WHERE option_name = 'siteurl'; UPDATE wp_options SET option_value = 'http://${aws_lb.wordpress_lb.dns_name}' WHERE option_name = 'home';"
              EOF
}

# Output do IP privado da MySQL Instance
output "mysql_private_ip" {
  value = aws_instance.mysql_instance.private_ip
}

# Criação da instância EC2 para rodar o Wordpress1
resource "aws_instance" "wordpress_instance1" {
  ami           = "ami-0866a3c8686eaeeba"  # Substitua com a AMI do Ubuntu mais recente
  instance_type = "t3.small"
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  iam_instance_profile    = aws_iam_instance_profile.ec2_instance_profile.name

  tags = {
    Name = "WordpressInstance1"
  }

  depends_on = [aws_instance.mysql_instance]

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y docker.io
              sudo systemctl start docker
              sudo systemctl enable docker
              sudo docker run -p 80:80 --name wordpress -e WORDPRESS_DB_HOST=${aws_instance.mysql_instance.private_ip}:3306 -e WORDPRESS_DB_USER=wpuser -e WORDPRESS_DB_PASSWORD=password -e WORDPRESS_DB_NAME=wordpress -d wordpress
              
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              sudo apt install unzip
              unzip awscliv2.zip
              sudo ./aws/install

              aws s3 cp s3://nuvem-wp-bkp/wp-content.tar ./wp-content.tar
              tar -xf wp-content.tar -C .

              sudo docker cp ./wp-content/. wordpress:/var/www/html/wp-content/
              EOF
}

resource "aws_instance" "wordpress_instance2" {
  ami           = "ami-0866a3c8686eaeeba"  # Substitua com a AMI do Ubuntu mais recente
  instance_type = "t3.small"
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  iam_instance_profile    = aws_iam_instance_profile.ec2_instance_profile.name

  tags = {
    Name = "WordpressInstance2"
  }

  depends_on = [aws_instance.mysql_instance]

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y docker.io
              sudo systemctl start docker
              sudo systemctl enable docker
              sudo docker run -p 80:80 --name wordpress -e WORDPRESS_DB_HOST=${aws_instance.mysql_instance.private_ip}:3306 -e WORDPRESS_DB_USER=wpuser -e WORDPRESS_DB_PASSWORD=password -e WORDPRESS_DB_NAME=wordpress -d wordpress
              
              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              sudo apt install unzip
              unzip awscliv2.zip
              sudo ./aws/install

              aws s3 cp s3://nuvem-wp-bkp/wp-content.tar ./wp-content.tar
              tar -xf wp-content.tar -C .

              sudo docker cp ./wp-content/. wordpress:/var/www/html/wp-content/
              EOF
}

resource "aws_instance" "locust_instance" {
  ami           = "ami-0866a3c8686eaeeba"  # Substitua com a AMI do Ubuntu mais recente
  instance_type = "t3.small"
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.public_sg.id]
  iam_instance_profile    = aws_iam_instance_profile.ec2_instance_profile.name

  tags = {
    Name = "LocustInstance"
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install -y python3-pip
              sudo apt install python3-locust -y

              curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
              sudo apt install unzip
              unzip awscliv2.zip
              sudo ./aws/install

              aws s3 cp s3://nuvem-wp-bkp/locustfile.py ./locustfile.py
              aws s3 cp s3://nuvem-wp-bkp/run_test.sh ./run_test.sh

              EOF
}

# Criação de um security group público para o Load Balancer
resource "aws_security_group" "public_lb_sg" {
  name        = "public-lb-sg"
  description = "Security group for public load balancer"
  vpc_id      = aws_vpc.main_vpc.id

  # Permitir tráfego HTTP de qualquer lugar
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permitir tráfego HTTPS de qualquer lugar (se necessário)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permitir todo tráfego de saída
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Criação do Load Balancer público
resource "aws_lb" "wordpress_lb" {
  name               = "wordpress-lb"
  internal           = false  # Tornar o Load Balancer público
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public_lb_sg.id]  # Grupo de segurança para o Load Balancer
  subnets            = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_b.id]  # Subnets públicas
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
