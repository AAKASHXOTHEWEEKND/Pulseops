#!/usr/bin/env bash
# Deploy one ECS service by registering a new task-definition revision that
# points at the given immutable image, then updating the service.
#
# The SAME image built once in CI is promoted here — we only swap the image
# reference in the task def; nothing is rebuilt.
#
#   deploy_service.sh <service: api|worker|web> <image-uri>
set -euo pipefail

SERVICE="${1:?service name required}"
IMAGE="${2:?image uri required}"
CLUSTER="${CLUSTER:-pulseops-staging-cluster}"
FAMILY="pulseops-staging-${SERVICE}"
CONTAINER="${SERVICE}"

echo ">> Fetching current task definition for ${FAMILY}"
TASKDEF=$(aws ecs describe-task-definition --task-definition "$FAMILY")

# Produce a new task def JSON: same everything, new image, drop read-only fields.
NEW_TASKDEF=$(echo "$TASKDEF" | jq --arg IMAGE "$IMAGE" --arg C "$CONTAINER" '
  .taskDefinition
  | .containerDefinitions = (.containerDefinitions | map(if .name == $C then .image = $IMAGE else . end))
  | {family, networkMode, requiresCompatibilities, cpu, memory, executionRoleArn, taskRoleArn, containerDefinitions, volumes, placementConstraints}
  | with_entries(select(.value != null))
')

echo ">> Registering new task definition revision"
NEW_ARN=$(aws ecs register-task-definition \
  --cli-input-json "$NEW_TASKDEF" \
  --query 'taskDefinition.taskDefinitionArn' --output text)
echo "   ${NEW_ARN}"

echo ">> Updating service ${FAMILY} -> new revision"
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$FAMILY" \
  --task-definition "$NEW_ARN" \
  >/dev/null

echo ">> ${SERVICE} update requested (circuit breaker will roll back on failure)."
