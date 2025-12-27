#!/bin/bash
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
sleep 90

COUNT=$(
  az policy state list \
    --subscription "$SUBSCRIPTION_ID" \
    --query "[?policyAssignmentName=='$ASSIGNMENT_NAME' && complianceState=='NonCompliant'] | length(@)" \
    -o tsv
)

echo "Non-compliant storage accounts (policy states): $COUNT"
if [ "${COUNT:-0}" -eq 0 ]; then
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
  --location-filters "$LOCATION" \
  -o none

echo "Remediation created. Waiting for completion..."
for i in $(seq 1 60); do
  STATE=$(az policy remediation show --subscription "$SUBSCRIPTION_ID" --name "$REM_NAME" --query provisioningState -o tsv)
  echo "[$i/60] provisioningState=$STATE"
  if [ "$STATE" = "Succeeded" ]; then
    echo "Remediation SUCCEEDED."
    exit 0
  fi
  if [ "$STATE" = "Failed" ]; then
    echo "Remediation FAILED. Showing deployments:"
    az policy remediation deployment list --subscription "$SUBSCRIPTION_ID" --name "$REM_NAME" -o table

    echo ""
    echo "Get exact ARM error using:"
    echo "az policy remediation deployment list --subscription $SUBSCRIPTION_ID --name $REM_NAME --query \"[].deploymentId\" -o tsv"
    exit 1
  fi
  sleep 20
done

echo "Timeout waiting remediation."
az policy remediation show --subscription "$SUBSCRIPTION_ID" --name "$REM_NAME" -o jsonc
exit 1
