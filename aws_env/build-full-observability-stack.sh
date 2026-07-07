#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-XXXXXXXXXXXXX}"
REPO_PREFIX="portfolio-observability"
IMAGE_TAG="${IMAGE_TAG:-latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ECS_CLUSTER_NAME="${ECS_CLUSTER_NAME:-observability-cluster}"
ECS_SERVICE_NAME="${ECS_SERVICE_NAME:-observability-service}"
ECS_TASK_FAMILY="${ECS_TASK_FAMILY:-observability-full-stack}"
ECS_EXECUTION_ROLE_NAME="${ECS_EXECUTION_ROLE_NAME:-ecsExecutionRoleForObsStack}"
ECS_SUBNET_IDS="${ECS_SUBNET_IDS:-}"
ECS_SECURITY_GROUP_IDS="${ECS_SECURITY_GROUP_IDS:-}"
ECS_ASSIGN_PUBLIC_IP="${ECS_ASSIGN_PUBLIC_IP:-ENABLED}"
TASK_DEFINITION_FILE="$REPO_ROOT/ecs-stack-manifest.json"

ensure_repository() {
  local repo_name="$1"
  # Ensure the ECR repository exists before pushing images to it.
  if ! aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" >/dev/null 2>&1; then
    aws ecr create-repository --repository-name "$repo_name" --region "$AWS_REGION" >/dev/null
  fi
}

build_and_push() {
  local service_name="$1"
  local context_dir="$2"
  local image_ref="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_PREFIX/$service_name:$IMAGE_TAG"

  # Build the container image from the service directory and push it to ECR.
  echo "Building $service_name from $context_dir"
  docker build -t "$image_ref" "$context_dir"
  docker push "$image_ref"
  echo "Pushed $image_ref"
}

ensure_execution_role() {
  local role_name="$1"
  local trust_policy_file
  trust_policy_file="$(mktemp)"

  # Create a trust policy that allows ECS tasks to assume the execution role.

  cat >"$trust_policy_file" <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  if ! aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
    # Create the IAM role if it does not already exist.
    aws iam create-role --role-name "$role_name" --assume-role-policy-document "file://$trust_policy_file" >/dev/null
  fi

  # Grant the role the standard ECS task execution permissions.
  aws iam attach-role-policy --role-name "$role_name" --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" >/dev/null 2>&1 || true
  rm -f "$trust_policy_file"
}

tag_resource() {
  local resource_arn="$1"
  # Apply a simple tag so the ECS resources are easy to identify in AWS.
  if [[ -n "$resource_arn" && "$resource_arn" != "None" ]]; then
    aws ecs tag-resource --resource-arn "$resource_arn" --tags key=Name,value="observability stack" --region "$AWS_REGION" >/dev/null 2>&1 || true
  fi
}

register_task_definition() {
  local execution_role_arn="$1"
  local temp_task_def
  temp_task_def="$(mktemp)"

  # Build a task definition JSON file with the ECS role and updated image references.

  python3 - "$TASK_DEFINITION_FILE" "$AWS_ACCOUNT_ID" "$AWS_REGION" "$execution_role_arn" "$ECS_TASK_FAMILY" >"$temp_task_def" <<'PY'
import json
import pathlib
import sys

source_path = pathlib.Path(sys.argv[1])
account_id = sys.argv[2]
region = sys.argv[3]
execution_role_arn = sys.argv[4]
family = sys.argv[5]

with source_path.open() as handle:
    task_def = json.load(handle)

task_def["family"] = family
task_def["executionRoleArn"] = execution_role_arn

for container in task_def.get("containerDefinitions", []):
    image = container.get("image", "")
    if "portfolio-observability" in image:
        container["image"] = image.replace("XXXXXXXXXXXXX", account_id).replace("us-east-1", region)

print(json.dumps(task_def, indent=2))
PY

  # Register the task definition with ECS so it can be used by the service.
  aws ecs register-task-definition --cli-input-json "file://$temp_task_def" --region "$AWS_REGION" >/dev/null
  rm -f "$temp_task_def"

  aws ecs describe-task-definition --task-definition "$ECS_TASK_FAMILY" --region "$AWS_REGION" --query 'taskDefinition.taskDefinitionArn' --output text
}

resolve_network_configuration() {
  # If subnet and security group values were provided, use them directly.
  if [[ -n "$ECS_SUBNET_IDS" && -n "$ECS_SECURITY_GROUP_IDS" ]]; then
    return 0
  fi

  local vpc_id
  local subnet_ids
  local default_security_group

  vpc_id="$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION" 2>/dev/null || true)"
  if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]; then
    echo "No default VPC found; skipping Fargate service creation."
    return 1
  fi

  if [[ -z "$ECS_SUBNET_IDS" ]]; then
    # Discover available subnets in the default VPC for Fargate placement.
    subnet_ids="$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[].SubnetId' --output text --region "$AWS_REGION" 2>/dev/null || true)"
    ECS_SUBNET_IDS="$(echo "$subnet_ids" | tr '\t' ',' | tr -d ' ' | sed 's/,$//' | sed 's/\s\+/,/g')"
  fi

  if [[ -z "$ECS_SECURITY_GROUP_IDS" ]]; then
    # Find the default security group for the VPC so the app can receive traffic.
    default_security_group="$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text --region "$AWS_REGION" 2>/dev/null || true)"
    if [[ -n "$default_security_group" && "$default_security_group" != "None" ]]; then
      ECS_SECURITY_GROUP_IDS="$default_security_group"
    fi
  fi

  if [[ -z "$ECS_SUBNET_IDS" || -z "$ECS_SECURITY_GROUP_IDS" ]]; then
    echo "Unable to discover VPC subnets or security groups; skipping Fargate service creation."
    return 1
  fi

  VPC_ID="$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION" 2>/dev/null || true)"
  SG_ID="$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text --region "$AWS_REGION" 2>/dev/null || true)"

  if [[ -n "$SG_ID" && "$SG_ID" != "None" ]]; then
    # Open the app and Prometheus ports in the default security group for inbound traffic.
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 5000 --cidr 0.0.0.0/0 --region "$AWS_REGION" 2>/dev/null || true
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 9090 --cidr 0.0.0.0/0 --region "$AWS_REGION" 2>/dev/null || true
  fi

  return 0
}

deploy_to_fargate() {
  local task_definition_arn="$1"

  # Create or update the ECS resources needed to run the observability stack on Fargate.

  if ! resolve_network_configuration; then
    echo "Cluster created, but Fargate service creation was skipped because networking details were unavailable."
    return 0
  fi

  # Create the ECS cluster if it does not already exist.
  aws ecs create-cluster --cluster-name "$ECS_CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || true

  local cluster_arn
  cluster_arn="$(aws ecs describe-clusters --clusters "$ECS_CLUSTER_NAME" --query 'clusters[0].clusterArn' --output text --region "$AWS_REGION" 2>/dev/null || true)"
  tag_resource "$cluster_arn"

  local subnets_json
  local sgs_json
  subnets_json="$(echo "[\"${ECS_SUBNET_IDS//,/\",\"}\"]" | sed 's/"",//g')"
  sgs_json="$(echo "[\"${ECS_SECURITY_GROUP_IDS//,/\",\"}\"]" | sed 's/"",//g')"

  local network_configuration
  network_configuration="{\"awsvpcConfiguration\":{\"subnets\":${subnets_json},\"securityGroups\":${sgs_json},\"assignPublicIp\":\"$ECS_ASSIGN_PUBLIC_IP\"}}"

  # Check service existence dynamically via query extraction instead of strict CLI exit codes
  local service_exists
  service_exists="$(aws ecs describe-services --cluster "$ECS_CLUSTER_NAME" --services "$ECS_SERVICE_NAME" --region "$AWS_REGION" --query 'services[0].status' --output text 2>/dev/null || echo "MISSING")"
  
  if [[ "$service_exists" != "MISSING" && "$service_exists" != "INACTIVE" && "$service_exists" != "None" ]]; then
    # Update the existing service to use the newly registered task definition.
    echo "Updating existing ECS service..."
    aws ecs update-service --cluster "$ECS_CLUSTER_NAME" --service "$ECS_SERVICE_NAME" --task-definition "$task_definition_arn" --desired-count 1 --network-configuration "$network_configuration" --region "$AWS_REGION" >/dev/null
  else
    # Create the ECS service from scratch when none exists yet.
    echo "Creating new ECS service..."
    aws ecs create-service --cluster "$ECS_CLUSTER_NAME" --service-name "$ECS_SERVICE_NAME" --task-definition "$task_definition_arn" --desired-count 1 --launch-type FARGATE --network-configuration "$network_configuration" --region "$AWS_REGION" >/dev/null
  fi

  local service_arn
  service_arn="$(aws ecs describe-services --cluster "$ECS_CLUSTER_NAME" --services "$ECS_SERVICE_NAME" --query 'services[0].serviceArn' --output text --region "$AWS_REGION" 2>/dev/null || true)"
  if [[ -n "$service_arn" && "$service_arn" != "None" ]]; then
    local service_id
    service_id="${service_arn##*/}"
    echo "ECS service ready: $service_id"
    tag_resource "$service_arn"
  fi
}

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required but was not found in PATH." >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI is required but was not found in PATH." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required but was not found in PATH." >&2
  exit 1
fi

aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

ensure_repository "$REPO_PREFIX/web-app"
ensure_repository "$REPO_PREFIX/prometheus"
ensure_repository "$REPO_PREFIX/grafana"

build_and_push "web-app" "$REPO_ROOT/app"
build_and_push "prometheus" "$REPO_ROOT/prometheus"
build_and_push "grafana" "$REPO_ROOT/grafana"

echo "Provisioning ECS cluster and task execution role..."
ensure_execution_role "$ECS_EXECUTION_ROLE_NAME"
EXECUTION_ROLE_ARN="$(aws iam get-role --role-name "$ECS_EXECUTION_ROLE_NAME" --query 'Role.Arn' --output text)"
TASK_DEFINITION_ARN="$(register_task_definition "$EXECUTION_ROLE_ARN")"
tag_resource "$TASK_DEFINITION_ARN"
deploy_to_fargate "$TASK_DEFINITION_ARN"

echo "Full observability stack images built and pushed successfully."
echo "Task definition registered and deployment flow completed."