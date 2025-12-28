#!/usr/bin/env bash
set -euo pipefail

RAW_SUB="${1:-}"
if [ -z "$RAW_SUB" ]; then
  echo "Subscription ID missing"
  exit 1
fi

SUBSCRIPTION_ID="${RAW_SUB##*/}"
ASSIGNMENT_NAME="deploy-storage-diagnostics-assignment"
LOCATION="francecentral"

echo "Using subscription: $SUBSCRIPTION_ID"
echo "Assignment: $ASSIGNMENT_NAME"
echo "Location: $LOCATION"

echo "Triggering Azure Policy evaluation..."
az policy state trigger-scan --subscription "$SUBSCRIPTION_ID" >/dev/null

# Azure policy evaluation can take time
sleep 90

NONCOMPLIANT_COUNT=$(
  az policy state list \
    --subscription "$SUBSCRIPTION_ID" \
    --query "[?policyAssignmentName=='$ASSIGNMENT_NAME' && complianceState=='NonCompliant'] | length(@)" \
    -o tsv
)

echo "Non-compliant storage accounts (policy states): ${NONCOMPLIANT_COUNT:-0}"

if [ "${NONCOMPLIANT_COUNT:-0}" -eq 0 ]; then
  echo "No remediation needed."
  exit 0
fi

REM_NAME="remediate-storage-diag-$(date +%s)"
echo "Creating remediation: $REM_NAME"

az policy remediation create \
  --name "$REM_NAME" \
  --subscription "$SUBSCRIPTION_ID" \
  --policy-assignment "$ASSIGNMENT_NAME" \
  --resource-discovery-mode ExistingNonCompliant \
  --location-filters "$LOCATION" >/dev/null

echo "Remediation created. Waiting for completion..."

for i in $(seq 1 60); do
  STATE=$(az policy remediation show \
    --subscription "$SUBSCRIPTION_ID" \
    --name "$REM_NAME" \
    --query "provisioningState" -o tsv || true)

  echo "[$i/60] provisioningState=${STATE:-unknown}"

  if [ "$STATE" = "Succeeded" ]; then
    echo "Remediation SUCCEEDED."
    exit 0
  fi

  if [ "$STATE" = "Failed" ]; then
    echo "Remediation FAILED. Showing deployments:"
    az policy remediation deployment list \
      --subscription "$SUBSCRIPTION_ID" \
      --name "$REM_NAME" \
      -o table || true

    echo ""
    echo "Dumping ARM errors for each deployment..."
    DEPLOY_IDS=$(az policy remediation deployment list \
      --subscription "$SUBSCRIPTION_ID" \
      --name "$REM_NAME" \
      --query "[].deploymentId" -o tsv || true)

    while read -r DEP; do
      [ -z "$DEP" ] && continue
      RG=$(echo "$DEP" | awk -F'/' '{for(i=1;i<=NF;i++){if($i=="resourceGroups"){print $(i+1); exit}}}')
      NAME=$(echo "$DEP" | awk -F'/' '{print $NF}')
      echo ""
      echo "Deployment: $NAME (RG: $RG)"
      az deployment group show -g "$RG" -n "$NAME" --query "properties.error" -o jsonc || true
    done <<< "$DEPLOY_IDS"

    exit 1
  fi

  sleep 20
done

echo "Timeout waiting for remediation completion."
exit 1
