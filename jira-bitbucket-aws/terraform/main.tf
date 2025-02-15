provider "aws" {
  region = "us-east-1"
}

# VPC and Subnets
resource "aws_vpc" "jira_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.jira_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.jira_vpc.id
  cidr_block = "10.0.2.0/24"
}

# Internet Gateway and Route Tables
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.jira_vpc.id
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.jira_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# NAT Gateway
resource "aws_eip" "nat_eip" {
  associate_with_private_ip = true
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.jira_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Security Groups
resource "aws_security_group" "jira_sg" {
  vpc_id = aws_vpc.jira_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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
}

resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.jira_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.jira_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS
resource "aws_db_instance" "jira_rds" {
  engine                 = "postgres"
  instance_class         = "db.t3.medium"
  allocated_storage      = 20
  multi_az               = true
  username               = "admin"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.jira_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  storage_encrypted      = true
  skip_final_snapshot    = true
}

resource "aws_db_subnet_group" "jira_subnet_group" {
  name       = "jira-subnet-group"
  subnet_ids = [aws_subnet.private_subnet.id]
}

# EFS
resource "aws_security_group" "efs_sg" {
  vpc_id = aws_vpc.jira_vpc.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.jira_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "jira_efs" {
  creation_token = "jira-efs"
  encrypted      = true
}

resource "aws_efs_mount_target" "jira_efs_mount" {
  file_system_id  = aws_efs_file_system.jira_efs.id
  subnet_id       = aws_subnet.private_subnet.id
  security_groups = [aws_security_group.efs_sg.id]
}

# S3
resource "aws_s3_bucket" "jira_logs" {
  bucket = "XXXXXXXXXXXXXXXX"
}

resource "aws_s3_bucket_lifecycle_configuration" "jira_logs_lifecycle" {
  bucket = aws_s3_bucket.jira_logs.id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "jira_cluster" {
  name = "jira-cluster"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "jira_task" {
  family                   = "jira"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048

  container_definitions = jsonencode([
    {
      name  = "jira"
      image = "atlassian/jira-software:latest"
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "jira_service" {
  name            = "jira-service"
  cluster         = aws_ecs_cluster.jira_cluster.id
  task_definition = aws_ecs_task_definition.jira_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.private_subnet.id]
    security_groups = [aws_security_group.jira_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.jira_tg.arn
    container_name   = "jira"
    container_port   = 8080
  }
}

# ALB
resource "aws_lb" "jira_alb" {
  name               = "jira-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.jira_sg.id]
  subnets            = [aws_subnet.public_subnet.id]
}

resource "aws_lb_target_group" "jira_tg" {
  name        = "jira-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.jira_vpc.id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }
}

resource "aws_lb_listener" "jira_listener" {
  load_balancer_arn = aws_lb.jira_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jira_tg.arn
  }
}

# Auto Scaling
resource "aws_appautoscaling_target" "ecs_target" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.jira_cluster.name}/${aws_ecs_service.jira_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 1
  max_capacity       = 10
}

resource "aws_appautoscaling_policy" "ecs_scaling_policy" {
  name               = "ecs-scaling-policy"
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70
  }
}
