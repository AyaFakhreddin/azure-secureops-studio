#!/bin/bash
set -e

# ===== Get subscription ID (accepts GUID or /subscriptions/ID) =====
RAW_SUB="$1"

if [ -z "$RAW_SUB" ]; then
  echo "❌ Subscription ID missing"
  exit 1
fi

# Remove /subscriptions/ if present
SUBSCRIPTION_ID="${RAW_SUB##*/}"

echo "✅ Using subscription ID: $SUBSCRIPTION_ID"

# ===== Force Azure Policy evaluation =====
echo "🔄 Triggering Azure Policy evaluation..."
az policy state trigger-scan --subscription "$SUBSCRIPTION_ID"

# Azure Policy evaluation is async
sleep 90

# =========================================================
# Stream Analytics - Deploy diagnostics to Log Analytics
# =========================================================
ASSIGNMENT_STREAM="aoss-assign-deploy-diagnostics-stream"

COUNT_STREAM=$(az policy state list \
  --subscription "$SUBSCRIPTION_ID" \
  --query "[?policyAssignmentName=='$ASSIGNMENT_STREAM' && complianceState=='NonCompliant'] | length(@)" \
  -o tsv)

echo "📊 Stream Analytics non-compliant count: $COUNT_STREAM"

if [ "$COUNT_STREAM" -gt 0 ]; then
  echo "🚑 Launching remediation for Stream Analytics diagnostics..."
  az policy remediation create \
    --name "remediate-stream-analytics-$(date +%s)" \
    --subscription "$SUBSCRIPTION_ID" \
    --policy-assignment "$ASSIGNMENT_STREAM" \
    --resource-discovery-mode ExistingNonCompliant
else
  echo "✅ No Stream Analytics remediation needed"
fi

# =========================================================
# Storage Accounts - Secure Transfer (HTTPS only)
# =========================================================
ASSIGNMENT_STORAGE="aoss-assign-remediate-secure-transfer-storage"

COUNT_STORAGE=$(az policy state list \
  --subscription "$SUBSCRIPTION_ID" \
  --query "[?policyAssignmentName=='$ASSIGNMENT_STORAGE' && complianceState=='NonCompliant'] | length(@)" \
  -o tsv)

echo "📊 Storage Accounts non-compliant count: $COUNT_STORAGE"

if [ "$COUNT_STORAGE" -gt 0 ]; then
  echo "🚑 Launching remediation for Storage secure transfer..."
  az policy remediation create \
    --name "remediate-secure-transfer-$(date +%s)" \
    --subscription "$SUBSCRIPTION_ID" \
    --policy-assignment "$ASSIGNMENT_STORAGE" \
    --resource-discovery-mode ExistingNonCompliant
else
  echo "✅ No Storage remediation needed"
fi

echo "🎉 Auto-remediation process completed successfully"
