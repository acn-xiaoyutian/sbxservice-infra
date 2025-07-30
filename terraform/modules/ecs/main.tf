# ECS module without ECR - ECR has been moved to another repository

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cluster"
  }
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_name}-${var.environment}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-execution-role"
  }
}

# Attach the AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}



# ECS Task Role
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-${var.environment}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-task-role"
  }
}

# Create a policy for CloudWatch Logs
resource "aws_iam_policy" "task_logs_policy" {
  name        = "${var.project_name}-${var.environment}-task-logs-policy"
  description = "Allow ECS tasks to send logs to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}



# Attach CloudWatch logs policy to task role
resource "aws_iam_role_policy_attachment" "task_logs" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.task_logs_policy.arn
}



# Create a policy for ECS Exec
resource "aws_iam_policy" "ecs_exec_policy" {
  name        = "${var.project_name}-${var.environment}-ecs-exec-policy"
  description = "Allow ECS Exec for task debugging"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach ECS Exec policy to task role
resource "aws_iam_role_policy_attachment" "task_ecs_exec" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_exec_policy.arn
}

# Create a policy for Kong Gateway secrets access
resource "aws_iam_policy" "kong_secrets_policy" {
  count       = var.kong_enabled ? 1 : 0
  name        = "${var.project_name}-${var.environment}-kong-secrets-policy"
  description = "Allow ECS tasks to read Kong Gateway secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.kong_cluster_cert[0].arn,
          aws_secretsmanager_secret.kong_cluster_cert_key[0].arn
        ]
      }
    ]
  })
}

# Attach Kong secrets policy to execution role (needed for retrieving secrets during startup)
resource "aws_iam_role_policy_attachment" "execution_kong_secrets" {
  count      = var.kong_enabled ? 1 : 0
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.kong_secrets_policy[0].arn
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}-${var.environment}"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-logs"
  }
}

# AWS Cloud Map Private DNS Namespace for service discovery
resource "aws_service_discovery_private_dns_namespace" "service_discovery" {
  name        = "${var.project_name}.${var.environment}.local"
  description = "Service discovery namespace for ${var.project_name} in ${var.environment}"
  vpc         = var.vpc_id

  tags = {
    Name = "${var.project_name}-${var.environment}-dns-namespace"
  }
}

# AWS Cloud Map Service for hello-service discovery
resource "aws_service_discovery_service" "hello_service" {
  name = var.project_name

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.service_discovery.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-hello-discovery-service"
  }
}

# AWS Cloud Map Service for Kong Gateway service discovery
resource "aws_service_discovery_service" "kong_gateway" {
  count = var.kong_enabled ? 1 : 0
  name  = "kong-gateway"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.service_discovery.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-kong-discovery-service"
  }
}



# ECS Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-${var.environment}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-${var.environment}-container"
      image     = var.container_image_url
      cpu       = var.task_cpu
      memory    = var.task_memory
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/actuator/health || exit 1"]
        interval    = 30
        retries     = 3
        timeout     = 5
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-${var.environment}-task"
  }
}

# CloudWatch Log Group for Kong Gateway
resource "aws_cloudwatch_log_group" "kong_app" {
  count             = var.kong_enabled ? 1 : 0
  name              = "/ecs/${var.project_name}-${var.environment}-kong"
  retention_in_days = 30

  tags = {
    Name = "${var.project_name}-${var.environment}-kong-logs"
  }
}

# AWS Secrets Manager secrets for Kong Gateway data plane certificates
resource "aws_secretsmanager_secret" "kong_cluster_cert" {
  count       = var.kong_enabled ? 1 : 0
  name        = "${var.project_name}-${var.environment}-kong-cluster-cert"
  description = "Kong Gateway data plane cluster certificate"

  tags = {
    Name = "${var.project_name}-${var.environment}-kong-cluster-cert"
  }
}

resource "aws_secretsmanager_secret_version" "kong_cluster_cert" {
  count         = var.kong_enabled ? 1 : 0
  secret_id     = aws_secretsmanager_secret.kong_cluster_cert[0].id
  secret_string = "-----BEGIN CERTIFICATE-----MIICBjCCAaygAwIBAgIBATAKBggqhkjOPQQDBDA0MTIwCQYDVQQGEwJJTjAlBgNVBAMeHgBrAG8AbgBuAGUAYwB0AC0ATABhAG0AcABQAE8AQzAeFw0yNTA3MzAwNDUzMTNaFw0zNTA3MzAwNDUzMTNaMDQxMjAJBgNVBAYTAklOMCUGA1UEAx4eAGsAbwBuAG4AZQBjAHQALQBMAGEAbQBwAFAATwBDMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEkmSUOQbcCnlD+b85MYYEkAdG3B6y/zt7fmhmbo376iULGoQRhemNFhc9PIVb8C5aHR7gTH90x0T2g2LmH+q6wqOBrjCBqzAMBgNVHRMBAf8EAjAAMAsGA1UdDwQEAwIABjAdBgNVHSUEFjAUBggrBgEFBQcDAQYIKwYBBQUHAwIwFwYJKwYBBAGCNxQCBAoMCGNlcnRUeXBlMCMGCSsGAQQBgjcVAgQWBBQBAQEBAQEBAQEBAQEBAQEBAQEBATAcBgkrBgEEAYI3FQcEDzANBgUpAQEBAQIBCgIBFDATBgkrBgEEAYI3FQEEBgIEABQACjAKBggqhkjOPQQDBANIADBFAiBcagvXb7a3wq5+72ybQF/WuTRsGUltcZPxeeLHvdyK0QIhAJUTSzA+aNZk9oUSkWtwn6PcKSBD/5y7ODL8d9TBOcPP-----END CERTIFICATE-----"
}

resource "aws_secretsmanager_secret" "kong_cluster_cert_key" {
  count       = var.kong_enabled ? 1 : 0
  name        = "${var.project_name}-${var.environment}-kong-cluster-cert-key"
  description = "Kong Gateway data plane cluster certificate private key"

  tags = {
    Name = "${var.project_name}-${var.environment}-kong-cluster-cert-key"
  }
}

resource "aws_secretsmanager_secret_version" "kong_cluster_cert_key" {
  count         = var.kong_enabled ? 1 : 0
  secret_id     = aws_secretsmanager_secret.kong_cluster_cert_key[0].id
  secret_string = "-----BEGIN PRIVATE KEY-----MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg62gtPExj4tm0ZE6nDoQp+btaGXzVdcfotyMpq8fEpTCgCgYIKoZIzj0DAQehRANCAASSZJQ5BtwKeUP5vzkxhgSQB0bcHrL/O3t+aGZujfvqJQsahBGF6Y0WFz08hVvwLlodHuBMf3THRPaDYuYf6rrC-----END PRIVATE KEY-----"
}

# Kong Gateway ECS Task Definition
resource "aws_ecs_task_definition" "kong_gateway" {
  count                    = var.kong_enabled ? 1 : 0
  family                   = "${var.project_name}-${var.environment}-kong-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-${var.environment}-kong-container"
      image     = "kong/kong-gateway:3.11"
      cpu       = var.task_cpu
      memory    = var.task_memory
      essential = true
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        },
        {
          containerPort = 8443
          hostPort      = 8443
          protocol      = "tcp"
        },
        {
          containerPort = 8100
          hostPort      = 8100
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.kong_app[0].name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "kong"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "kong health || exit 1"]
        interval    = 30
        retries     = 3
        timeout     = 5
        startPeriod = 60
      }
      environment = [
        {
          name  = "KONG_ROLE"
          value = "data_plane"
        },
        {
          name  = "KONG_DATABASE"
          value = "off"
        },
        {
          name  = "KONG_VITALS"
          value = "off"
        },
        {
          name  = "KONG_CLUSTER_MTLS"
          value = "pki"
        },
        {
          name  = "KONG_CLUSTER_CONTROL_PLANE"
          value = "d7c265783e.in.cp0.konghq.com:443"
        },
        {
          name  = "KONG_CLUSTER_SERVER_NAME"
          value = "d7c265783e.in.cp0.konghq.com"
        },
        {
          name  = "KONG_CLUSTER_TELEMETRY_ENDPOINT"
          value = "d7c265783e.in.tp0.konghq.com:443"
        },
        {
          name  = "KONG_CLUSTER_TELEMETRY_SERVER_NAME"
          value = "d7c265783e.in.tp0.konghq.com"
        },
        {
          name  = "KONG_LUA_SSL_TRUSTED_CERTIFICATE"
          value = "system"
        },
        {
          name  = "KONG_KONNECT_MODE"
          value = "on"
        },
        {
          name  = "KONG_CLUSTER_DP_LABELS"
          value = "type:ecs-fargate"
        },
        {
          name  = "KONG_ROUTER_FLAVOR"
          value = "expressions"
        },
        {
          name  = "KONG_STATUS_LISTEN"
          value = "0.0.0.0:8100"
        }
      ]
      secrets = [
        {
          name      = "KONG_CLUSTER_CERT"
          valueFrom = aws_secretsmanager_secret.kong_cluster_cert[0].arn
        },
        {
          name      = "KONG_CLUSTER_CERT_KEY"
          valueFrom = aws_secretsmanager_secret.kong_cluster_cert_key[0].arn
        }
      ]
    }
  ])

  tags = {
    Name = "${var.project_name}-${var.environment}-kong-task"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.public_sg_id]
  subnets            = var.public_subnets

  enable_deletion_protection = false
  idle_timeout               = 25

  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.project_name}-${var.environment}-alb"
  }
}

# Target Group for ALB - points to Kong Gateway NLB when Kong is enabled
resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-${var.environment}-tg"
  port        = var.kong_enabled ? 8000 : var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.kong_enabled ? "/" : "/actuator/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = var.kong_enabled ? "200-399" : "200"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-tg"
  }
}

# Data source to get Kong NLB IP addresses for ALB target group
data "aws_network_interface" "kong_nlb_eni" {
  count = var.kong_enabled ? length(var.private_subnets) : 0

  filter {
    name   = "description"
    values = ["ELB ${aws_lb.kong_nlb[0].arn_suffix}"]
  }

  filter {
    name   = "subnet-id"
    values = [var.private_subnets[count.index]]
  }
}

# Target Group Attachment for Kong NLB IPs (when Kong is enabled)
resource "aws_lb_target_group_attachment" "kong_nlb" {
  count            = var.kong_enabled ? length(var.private_subnets) : 0
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = data.aws_network_interface.kong_nlb_eni[count.index].private_ip
  port             = 8000

  depends_on = [aws_lb.kong_nlb]
}

# ALB Listener for HTTPS (when certificate is provided)
resource "aws_lb_listener" "https" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ALB Listener for HTTP (always present)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ECS Service
resource "aws_ecs_service" "app" {
  name                               = "${var.project_name}-${var.environment}-service"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.app.arn
  desired_count                      = var.app_count
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  launch_type                        = "FARGATE"
  scheduling_strategy                = "REPLICA"
  enable_execute_command             = true

  network_configuration {
    security_groups  = [var.application_sg_id]
    subnets          = var.private_subnets
    assign_public_ip = false
  }

  # Only attach to ALB if Kong is not enabled
  dynamic "load_balancer" {
    for_each = var.kong_enabled ? [] : [1]
    content {
      target_group_arn = aws_lb_target_group.app.arn
      container_name   = "${var.project_name}-${var.environment}-container"
      container_port   = var.container_port
    }
  }

  # Register service in Cloud Map for service discovery
  service_registries {
    registry_arn = aws_service_discovery_service.hello_service.arn
  }

  depends_on = [
    aws_lb_listener.http,
    aws_lb_listener.https
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-service"
  }
}

# Network Load Balancer for Kong Gateway
resource "aws_lb" "kong_nlb" {
  count              = var.kong_enabled ? 1 : 0
  name               = "${var.project_name}-${var.environment}-kong-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.private_subnets

  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true

  tags = {
    Name = "${var.project_name}-${var.environment}-kong-nlb"
  }
}

# Target Group for Kong Gateway NLB
resource "aws_lb_target_group" "kong" {
  count       = var.kong_enabled ? 1 : 0
  name        = "${var.project_name}-${var.environment}-kong-tg"
  port        = 8000
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    protocol            = "HTTP"
    port                = "8100"
    path                = "/status/ready"
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-kong-tg"
  }
}

# NLB Listener for Kong Gateway
resource "aws_lb_listener" "kong_nlb" {
  count             = var.kong_enabled ? 1 : 0
  load_balancer_arn = aws_lb.kong_nlb[0].arn
  port              = "8000"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.kong[0].arn
  }
}

# Kong Gateway ECS Service
resource "aws_ecs_service" "kong_gateway" {
  count                              = var.kong_enabled ? 1 : 0
  name                               = "${var.project_name}-${var.environment}-kong-service"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.kong_gateway[0].arn
  desired_count                      = var.kong_app_count
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  launch_type                        = "FARGATE"
  scheduling_strategy                = "REPLICA"
  enable_execute_command             = true

  network_configuration {
    security_groups  = [var.application_sg_id]
    subnets          = var.private_subnets
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.kong[0].arn
    container_name   = "${var.project_name}-${var.environment}-kong-container"
    container_port   = 8000
  }

  # Register Kong Gateway service in Cloud Map for service discovery
  service_registries {
    registry_arn = aws_service_discovery_service.kong_gateway[0].arn
  }

  depends_on = [
    aws_lb_listener.kong_nlb
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-kong-service"
  }
} 