locals {
  ssm_arn = "arn:aws:ssm:${var.region}:${local.account_id}:parameter${local.ssm_prefix}"

  # Shared container environment (both the init and web containers). ECS env values are strings.
  base_env = [
    { name = "DJANGO_ALLOW_ASYNC_UNSAFE", value = "true" },
    { name = "PORTAL_ALLOWED_HOSTS", value = local.portal_allowed_hosts },
    { name = "TETHYS_DB_ENGINE", value = "django.db.backends.postgresql" },
    { name = "TETHYS_DB_NAME", value = var.db_name },
    { name = "TETHYS_DB_HOST", value = var.db_host },
    { name = "TETHYS_DB_PORT", value = tostring(var.db_port) },
    { name = "TETHYS_DB_USERNAME", value = var.db_username },
    # 'direct' or 'transaction' -> portal-config.sh sets DISABLE_SERVER_SIDE_CURSORS (DB-agnostic).
    { name = "TETHYS_DB_POOL_MODE", value = var.db_pool_mode },
    { name = "TETHYS_PORT", value = tostring(var.web_port) },
    { name = "ASGI_PROCESSES", value = var.asgi_processes },
    { name = "SERVER", value = var.server }, # uvicorn | gunicorn (gunicorn manages uvicorn workers)
    { name = "INIT_VERSION", value = var.init_version },
    { name = "AWS_REGION", value = var.region },
    { name = "AWS_DEFAULT_REGION", value = var.region },
    { name = "STATIC_S3_BUCKET", value = var.static_bucket_name },
    { name = "STATIC_CLOUDFRONT_DOMAIN", value = aws_cloudfront_distribution.this.domain_name },
    { name = "POSTGIS_SERVICE_NAME", value = "primary_postgis" },
    { name = "GEOGLOWS_CACHE_BACKEND", value = var.geoglows_cache_backend },
    { name = "GEOGLOWS_CACHE_BUCKET", value = var.static_bucket_name },
    { name = "GEOGLOWS_CACHE_PREFIX", value = var.geoglows_cache_prefix },
  ]

  web_secrets = [
    { name = "TETHYS_DB_PASSWORD", valueFrom = "${local.ssm_arn}/db-password" },
    { name = "TETHYS_PS_CONNECTION", valueFrom = "${local.ssm_arn}/ps-connection" },
    { name = "TETHYS_SECRET_KEY", valueFrom = "${local.ssm_arn}/secret-key" },
  ]
  init_secrets = concat(local.web_secrets, [
    { name = "PORTAL_SUPERUSER_PASSWORD", valueFrom = "${local.ssm_arn}/portal-superuser-password" },
  ])
}

resource "aws_ecs_task_definition" "portal" {
  family                   = "${local.name}-web"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.exec.arn
  task_role_arn            = aws_iam_role.task.arn
  tags                     = local.tags

  container_definitions = jsonencode([
    # init container: runs init-tethys.sh once per task start, then exits (essential:false)
    {
      name        = "init"
      image       = var.image_uri
      essential   = false
      command     = ["/usr/local/bin/init-tethys.sh"]
      environment = concat(local.base_env, [{ name = "PORTAL_SUPERUSER_NAME", value = "admin" }])
      secrets     = local.init_secrets
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.portal.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "init"
        }
      }
    },
    # web container: ASGI server (uvicorn or gunicorn per var.server), starts after init SUCCESS
    {
      name         = "web"
      image        = var.image_uri
      essential    = true
      command      = ["/usr/local/bin/start-server.sh"]
      dependsOn    = [{ containerName = "init", condition = "SUCCESS" }]
      portMappings = [{ containerPort = var.web_port, protocol = "tcp" }]
      environment  = local.base_env
      secrets      = local.web_secrets
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.portal.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "web"
        }
      }
    },
  ])
}

resource "aws_ecs_service" "portal" {
  name                              = "${local.name}-web"
  cluster                           = aws_ecs_cluster.this.arn
  task_definition                   = aws_ecs_task_definition.portal.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  platform_version                  = "LATEST"
  health_check_grace_period_seconds = 180

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.service_subnets
    security_groups  = [aws_security_group.web.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.portal.arn
    container_name   = "web"
    container_port   = var.web_port
  }

  propagate_tags = "SERVICE"
  tags           = local.tags

  depends_on = [aws_lb_listener.http]
}
