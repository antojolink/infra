variable "env" {
  type = string
}

variable "instance_id" {
  type = string
}

variable "db_identifier" {
  type = string
}

variable "log_group" {
  type = string
}

data "aws_region" "current" {}

locals {
  namespace = "AntojoLink/${var.env}"
  region    = data.aws_region.current.region
}

# Cuenta cada request que registra pino-http ("request completed")
resource "aws_cloudwatch_log_metric_filter" "requests" {
  name           = "antojolink-${var.env}-requests"
  log_group_name = var.log_group
  pattern        = "{ $.msg = \"request completed\" }"

  metric_transformation {
    name          = "Requests"
    namespace     = local.namespace
    value         = "1"
    default_value = "0"
  }
}

# Cuenta los mensajes con nivel error
resource "aws_cloudwatch_log_metric_filter" "errors" {
  name           = "antojolink-${var.env}-errors"
  log_group_name = var.log_group
  pattern        = "{ $.level = \"error\" }"

  metric_transformation {
    name          = "Errors"
    namespace     = local.namespace
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "antojolink-${var.env}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 8, height = 6
        properties = {
          title  = "EC2 - CPU (%)"
          region = local.region
          stat   = "Average"
          period = 60
          metrics = [["AWS/EC2", "CPUUtilization", "InstanceId", var.instance_id]]
        }
      },
      {
        type = "metric", x = 8, y = 0, width = 8, height = 6
        properties = {
          title  = "EC2 - Memoria (%)"
          region = local.region
          stat   = "Average"
          period = 60
          metrics = [["CWAgent", "mem_used_percent", "InstanceId", var.instance_id]]
        }
      },
      {
        type = "metric", x = 16, y = 0, width = 8, height = 6
        properties = {
          title  = "API - Requests y errores por minuto"
          region = local.region
          stat   = "Sum"
          period = 60
          metrics = [
            [local.namespace, "Requests"],
            [local.namespace, "Errors"]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 8, height = 6
        properties = {
          title  = "RDS - CPU (%)"
          region = local.region
          stat   = "Average"
          period = 60
          metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_identifier]]
        }
      },
      {
        type = "metric", x = 8, y = 6, width = 8, height = 6
        properties = {
          title  = "RDS - Conexiones"
          region = local.region
          stat   = "Average"
          period = 60
          metrics = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_identifier]]
        }
      },
      {
        type = "log", x = 16, y = 6, width = 8, height = 6
        properties = {
          title  = "API - Ultimos errores"
          region = local.region
          query  = "SOURCE '${var.log_group}' | fields @timestamp, msg, err.message | filter level = 'error' | sort @timestamp desc | limit 20"
          view   = "table"
        }
      }
    ]
  })
}

output "dashboard_url" {
  value = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.this.dashboard_name}"
}
