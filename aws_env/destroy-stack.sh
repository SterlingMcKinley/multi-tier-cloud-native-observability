#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-XXXXXXXXXXX}"
REPO_PREFIX="portfolio-observability"
IMAGE_TAG="${IMAGE_TAG:-latest}"
ECS_CLUSTER_NAME="${ECS_CLUSTER_NAME:-observability-cluster}"
ECS_SERVICE_NAME="${ECS_SERVICE_NAME:-observability-service}"
ECS_TASK_FAMILY="${ECS_TASK_FAMILY:-observability-full-stack}"
ECS_EXECUTION_ROLE_NAME="${ECS_EXECUTION_ROLE_NAME:-ecsExecutionRoleForObsStack}"

delete_repository() {
  local repo_name="$1"
  echo "Deleting ECR repository: $repo_name"
  aws ecr delete-repository \
    --repository-name "$repo_name" \
    --force \
    --region "$AWS_REGION" >/dev/null 2>&1 || true
}

remove_local_image() {
  local image_ref="$1"
  echo "Removing local image: $image_ref"
  docker rmi "$image_ref" >/dev/null 2>&1 || true
}

delete_ecs_service() {
  echo "Deleting ECS service: $ECS_SERVICE_NAME"
  aws ecs update-service \
    --cluster "$ECS_CLUSTER_NAME" \
    --service "$ECS_SERVICE_NAME" \
    --desired-count 0 \
    --region "$AWS_REGION" >/dev/null 2>&1 || true

  aws ecs delete-service \
    --cluster "$ECS_CLUSTER_NAME" \
    --service "$ECS_SERVICE_NAME" \
    --region "$AWS_REGION" >/dev/null 2>&1 || true
}

delete_task_definitions() {
  echo "Deregistering ECS task definitions for family: $ECS_TASK_FAMILY"
  local task_def_arns
  task_def_arns="$(aws ecs list-task-definitions --family-prefix "$ECS_TASK_FAMILY" --region "$AWS_REGION" --query 'taskDefinitionArns' --output text 2>/dev/null || true)"

  for task_def_arn in $task_def_arns; do
    aws ecs deregister-task-definition \
      --task-definition "$task_def_arn" \
      --region "$AWS_REGION" >/dev/null 2>&1 || true
  done
}

delete_ecs_cluster() {
  echo "Deleting ECS cluster: $ECS_CLUSTER_NAME"
  aws ecs delete-cluster \
    --cluster "$ECS_CLUSTER_NAME" \
    --region "$AWS_REGION" >/dev/null 2>&1 || true
}

delete_execution_role() {
  echo "Deleting IAM execution role: $ECS_EXECUTION_ROLE_NAME"
  aws iam detach-role-policy \
    --role-name "$ECS_EXECUTION_ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" >/dev/null 2>&1 || true

  aws iam delete-role \
    --role-name "$ECS_EXECUTION_ROLE_NAME" >/dev/null 2>&1 || true
}

revoke_security_group_rules() {
  local vpc_id
  local sg_id

  vpc_id="$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION" 2>/dev/null || true)"
  sg_id="$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text --region "$AWS_REGION" 2>/dev/null || true)"

  if [[ -n "$sg_id" && "$sg_id" != "None" ]]; then
    echo "Revoking security group ingress rules for $sg_id"
    aws ec2 revoke-security-group-ingress --group-id "$sg_id" --protocol tcp --port 5000 --cidr 0.0.0.0/0 --region "$AWS_REGION" >/dev/null 2>&1 || true
    aws ec2 revoke-security-group-ingress --group-id "$sg_id" --protocol tcp --port 9090 --cidr 0.0.0.0/0 --region "$AWS_REGION" >/dev/null 2>&1 || true
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

delete_repository "$REPO_PREFIX/web-app"
delete_repository "$REPO_PREFIX/prometheus"
delete_repository "$REPO_PREFIX/grafana"

remove_local_image "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_PREFIX/web-app:$IMAGE_TAG"
remove_local_image "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_PREFIX/prometheus:$IMAGE_TAG"
remove_local_image "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO_PREFIX/grafana:$IMAGE_TAG"

delete_ecs_service
delete_task_definitions
delete_ecs_cluster
delete_execution_role
revoke_security_group_rules

echo "Cleanup complete."
