#!/bin/bash
set -e

SUBSCRIPTION_ID="$1"

if [ -z "$SUBSCRIPTION_ID" ]; then
  echo "Subscription ID missing"
  exit 1
fi

echo "Triggering Azure Policy evaluation..."
az policy state trigger-scan --subscription "$SUBSCRIPTION_ID"
sleep 90

# ---- Stream Analytics remediation ----
ASSIGNMENT_STREAM="aoss-assign-deploy-diagnostics-stream"

COUNT_STREAM=$(az policy state list \
  --subscription "$SUBSCRIPTION_ID" \
  --query "[?policyAssignmentName=='$ASSIGNMENT_STREAM' && complianceState=='NonCompliant'] | length(@)" \
  -o tsv)

if [ "$COUNT_STREAM" -gt 0 ]; then
  echo "Remediating Stream Analytics diagnostics..."
  az policy remediation create \
    --name "remediate-stream-analytics-$(date +%s)" \
    --subscription "$SUBSCRIPTION_ID" \
    --policy-assignment "$ASSIGNMENT_STREAM" \
    --resource-discovery-mode ExistingNonCompliant
fi

# ---- Secure Transfer remediation ----
ASSIGNMENT_STORAGE="aoss-assign-remediate-secure-transfer-storage"

COUNT_STORAGE=$(az policy state list \
  --subscription "$SUBSCRIPTION_ID" \
  --query "[?policyAssignmentName=='$ASSIGNMENT_STORAGE' && complianceState=='NonCompliant'] | length(@)" \
  -o tsv)

if [ "$COUNT_STORAGE" -gt 0 ]; then
  echo "Remediating Storage secure transfer..."
  az policy remediation create \
    --name "remediate-secure-transfer-$(date +%s)" \
    --subscription "$SUBSCRIPTION_ID" \
    --policy-assignment "$ASSIGNMENT_STORAGE" \
    --resource-discovery-mode ExistingNonCompliant
fi
