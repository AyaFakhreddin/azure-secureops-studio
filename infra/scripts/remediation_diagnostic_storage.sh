#!/usr/bin/env bash
set -euo pipefail

RAW_SUB="${1:-}"
ASSIGNMENT_NAME="${2:-deploy-storage-diagnostics-assignment}"

if [[ -z "$RAW_SUB" ]]; then
  echo "Usage: $0 <subscriptionId or /subscriptions/id> [policy_assignment_name]"
  exit 1
fi

SUBSCRIPTION_ID="${RAW_SUB##*/}"
echo "Using subscription ID: $SUBSCRIPTION_ID"
echo "Assignment: $ASSIGNMENT_NAME"

az account set --subscription "$SUBSCRIPTION_ID" >/dev/null

echo "Triggering Azure Policy evaluation..."
az policy state trigger-scan --subscription "$SUBSCRIPTION_ID" >/dev/null
sleep 90

COUNT=$(az policy state list \
  --subscription "$SUBSCRIPTION_ID" \
  --query "[?policyAssignmentName=='$ASSIGNMENT_NAME' && complianceState=='NonCompliant'] | length(@)" \
  -o tsv)

echo "Non-compliant storage accounts: $COUNT"

if [[ "$COUNT" -eq 0 ]]; then
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
  -o jsonc

echo "Done."
