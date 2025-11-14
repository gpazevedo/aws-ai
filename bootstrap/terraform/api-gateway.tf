# =============================================================================
# API Gateway Configuration (Optional)
# =============================================================================
# Uncomment this file to use API Gateway instead of Lambda Function URLs
# =============================================================================

# API Gateway REST API
resource "aws_api_gateway_rest_api" "api" {
  count = var.enable_api_gateway ? 1 : 0

  name        = "${var.project_name}-${var.environment}-api"
  description = "API Gateway for ${var.project_name} ${var.environment}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Root resource proxy
resource "aws_api_gateway_resource" "proxy" {
  count = var.enable_api_gateway ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.api[0].id
  parent_id   = aws_api_gateway_rest_api.api[0].root_resource_id
  path_part   = "{proxy+}"
}

# ANY method for proxy
resource "aws_api_gateway_method" "proxy" {
  count = var.enable_api_gateway ? 1 : 0

  rest_api_id   = aws_api_gateway_rest_api.api[0].id
  resource_id   = aws_api_gateway_resource.proxy[0].id
  http_method   = "ANY"
  authorization = "NONE"
}

# Lambda integration
resource "aws_api_gateway_integration" "lambda" {
  count = var.enable_api_gateway ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.api[0].id
  resource_id = aws_api_gateway_method.proxy[0].resource_id
  http_method = aws_api_gateway_method.proxy[0].http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api.invoke_arn
}

# Deployment
resource "aws_api_gateway_deployment" "api" {
  count = var.enable_api_gateway ? 1 : 0

  depends_on = [
    aws_api_gateway_integration.lambda
  ]

  rest_api_id = aws_api_gateway_rest_api.api[0].id

  lifecycle {
    create_before_destroy = true
  }
}

# Stage
resource "aws_api_gateway_stage" "api" {
  count = var.enable_api_gateway ? 1 : 0

  deployment_id = aws_api_gateway_deployment.api[0].id
  rest_api_id   = aws_api_gateway_rest_api.api[0].id
  stage_name    = var.environment
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  count = var.enable_api_gateway ? 1 : 0

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api[0].execution_arn}/*/*"
}
