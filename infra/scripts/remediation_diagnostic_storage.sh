#!/usr/bin/env bash
set -euo pipefail

RAW_SUB="${1:-}"
ASSIGNMENT_NAME="${2:-deploy-storage-diagnostics-assignment}"
LOCATION="${3:-francecentral}"

if [[ -z "$RAW_SUB" ]]; then
  echo "Usage: $0 <SUBSCRIPTION_ID_OR_RESOURCE_ID> [ASSIGNMENT_NAME] [LOCATION]"
  exit 1
fi

SUBSCRIPTION_ID="${RAW_SUB##*/}"
echo "Using subscription: $SUBSCRIPTION_ID"
echo "Assignment: $ASSIGNMENT_NAME"
echo "Location: $LOCATION"

echo "Triggering Azure Policy evaluation..."
az policy state trigger-scan --subscription "$SUBSCRIPTION_ID" >/dev/null || true

sleep 60

# Count noncompliant resources by policy states
COUNT=$(az policy state list \
  --subscription "$SUBSCRIPTION_ID" \
  --query "[?policyAssignmentName=='$ASSIGNMENT_NAME' && complianceState=='NonCompliant'] | length(@)" \
  -o tsv)

echo "Non-compliant storage accounts (policy states): $COUNT"

if [[ "${COUNT:-0}" -eq 0 ]]; then
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
  --location "$LOCATION" >/dev/null

echo "Remediation created. Waiting for completion..."

STATE=""
for i in $(seq 1 60); do
  STATE=$(az policy remediation show \
    --subscription "$SUBSCRIPTION_ID" \
    --name "$REM_NAME" \
    --query provisioningState -o tsv 2>/dev/null || echo "")
  echo "[$i/60] provisioningState=$STATE"
  [[ "$STATE" == "Succeeded" ]] && break
  [[ "$STATE" == "Failed" ]] && break
  sleep 10
done

if [[ "$STATE" != "Succeeded" ]]; then
  echo "Remediation FAILED. Showing deployments:"
  az policy remediation deployment list \
    --subscription "$SUBSCRIPTION_ID" \
    --name "$REM_NAME" -o table || true

  echo "Dumping ARM errors for each deployment..."
  DEPLOY_IDS=$(az policy remediation deployment list \
    --subscription "$SUBSCRIPTION_ID" \
    --name "$REM_NAME" --query "[].deploymentId" -o tsv)

  while IFS= read -r DEPLOY_ID; do
    [[ -z "$DEPLOY_ID" ]] && continue

    # DEPLOY_ID format:
    # /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Resources/deployments/<name>
    RG=$(echo "$DEPLOY_ID" | awk -F/ '{for(i=1;i<=NF;i++){ if($i=="resourceGroups"){ print $(i+1); exit } }}')
    DNAME=$(basename "$DEPLOY_ID")

    echo "Deployment: $DNAME (RG: $RG)"
    az deployment group show \
      --resource-group "$RG" \
      --name "$DNAME" \
      --query "properties.error" -o jsonc || true

    az deployment operation group list \
      --resource-group "$RG" \
      --name "$DNAME" \
      --query "[?properties.provisioningState=='Failed'].properties.statusMessage" -o jsonc || true

  done <<< "$DEPLOY_IDS"

  exit 1
fi

echo "Remediation SUCCEEDED."
