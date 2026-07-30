#!/usr/bin/env bash
# Run Alembic migrations as a one-off ECS task using the API task definition,
# overriding the command to `alembic upgrade head`. Waits for completion and
# fails the pipeline (non-zero) if the migration task exits non-zero.
#
#   run_migrations.sh <image-uri>
set -euo pipefail

IMAGE="${1:?image uri required}"
CLUSTER="${CLUSTER:-pulseops-staging-cluster}"
FAMILY="pulseops-staging-api"

# Discover networking from the running API service so the task lands in the
# same private subnets / security group (and can reach the DB).
NETCFG=$(aws ecs describe-services --cluster "$CLUSTER" --services "$FAMILY" \
  --query 'services[0].networkConfiguration.awsvpcConfiguration' --output json)
SUBNETS=$(echo "$NETCFG" | jq -r '.subnets | join(",")')
SGS=$(echo "$NETCFG" | jq -r '.securityGroups | join(",")')

echo ">> Launching migration task"
TASK_ARN=$(aws ecs run-task \
  --cluster "$CLUSTER" \
  --task-definition "$FAMILY" \
  --launch-type FARGATE \
  --count 1 \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SGS],assignPublicIp=DISABLED}" \
  --overrides "{\"containerOverrides\":[{\"name\":\"api\",\"command\":[\"alembic\",\"upgrade\",\"head\"],\"image\":\"$IMAGE\"}]}" \
  --query 'tasks[0].taskArn' --output text)

echo ">> Waiting for migration task to stop: $TASK_ARN"
aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN"

EXIT_CODE=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
  --query 'tasks[0].containers[0].exitCode' --output text)

echo ">> Migration task exit code: ${EXIT_CODE}"
if [ "$EXIT_CODE" != "0" ]; then
  echo "!! Migration failed — aborting deploy (app not rolled out)."
  exit 1
fi
echo ">> Migrations applied successfully."
