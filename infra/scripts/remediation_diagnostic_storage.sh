#!/usr/bin/env bash
set -euo pipefail

RAW_SUB="${1:-}"
ASSIGNMENT_NAME="${2:-deploy-storage-diagnostics-assignment}"
LOCATION="${3:-francecentral}"

if [[ -z "$RAW_SUB" ]]; then
  echo "Usage: $0 <subscriptionId or /subscriptions/id> [assignment_name] [location]"
  exit 1
fi

SUBSCRIPTION_ID="${RAW_SUB##*/}"
echo "Using subscription ID: $SUBSCRIPTION_ID"
echo "Assignment: $ASSIGNMENT_NAME"
echo "Location: $LOCATION"

az account set --subscription "$SUBSCRIPTION_ID" >/dev/null

echo "Triggering Azure Policy evaluation..."
az policy state trigger-scan --subscription "$SUBSCRIPTION_ID" >/dev/null

# Give Policy Insights time to update (important)
sleep 240

ASSIGNMENT_ID="/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.Authorization/policyAssignments/${ASSIGNMENT_NAME}"
REM_NAME="remediate-storage-diag-$(date +%s)"

echo "Creating remediation: $REM_NAME"
az policy remediation create \
  --name "$REM_NAME" \
  --subscription "$SUBSCRIPTION_ID" \
  --policy-assignment "$ASSIGNMENT_ID" \
  --resource-discovery-mode ExistingNonCompliant \
  --location "$LOCATION" \
  >/dev/null

echo "Remediation created. Waiting for completion..."
for i in {1..40}; do
  STATE=$(az policy remediation show \
    --subscription "$SUBSCRIPTION_ID" \
    --name "$REM_NAME" \
    --query provisioningState -o tsv)

  echo "[$i/40] provisioningState=$STATE"
  if [[ "$STATE" == "Succeeded" || "$STATE" == "Failed" ]]; then
    break
  fi
  sleep 20
done

echo "Remediation status:"
az policy remediation show --subscription "$SUBSCRIPTION_ID" --name "$REM_NAME" -o jsonc

echo "Deployment details per resource:"
az policy remediation deployment list --subscription "$SUBSCRIPTION_ID" --name "$REM_NAME" -o table
