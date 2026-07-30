#!/usr/bin/env bash
# Roll a service back to its previous task-definition revision.
# ECS keeps every revision, so rollback is "point the service at revision N-1".
#
#   rollback.sh <service: api|worker|web> [revisions-back:1]
set -euo pipefail

SERVICE="${1:?service name required}"
BACK="${2:-1}"
CLUSTER="${CLUSTER:-pulseops-staging-cluster}"
FAMILY="pulseops-staging-${SERVICE}"

CURRENT=$(aws ecs describe-task-definition --task-definition "$FAMILY" \
  --query 'taskDefinition.revision' --output text)
TARGET=$((CURRENT - BACK))

if [ "$TARGET" -lt 1 ]; then
  echo "!! No revision ${TARGET} to roll back to (current=${CURRENT})."
  exit 1
fi

echo ">> Rolling ${FAMILY} back: revision ${CURRENT} -> ${TARGET}"
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$FAMILY" \
  --task-definition "${FAMILY}:${TARGET}" \
  >/dev/null

aws ecs wait services-stable --cluster "$CLUSTER" --services "$FAMILY"
echo ">> Rollback complete. Verify with the smoke test."
