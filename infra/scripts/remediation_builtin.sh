#!/bin/bash
set -e

RAW_SUB="$1"
if [ -z "$RAW_SUB" ]; then
  echo "Subscription ID missing"
  exit 1
fi

SUBSCRIPTION_ID="${RAW_SUB##*/}"
echo "Using subscription ID: $SUBSCRIPTION_ID"

trigger_scan () {
  echo "Triggering Azure Policy evaluation..."
  az policy state trigger-scan --subscription "$SUBSCRIPTION_ID" >/dev/null
}

noncompliant_count () {
  local ASSIGNMENT_NAME="$1"
  az policy state list \
    --subscription "$SUBSCRIPTION_ID" \
    --query "[?policyAssignmentName=='$ASSIGNMENT_NAME' && complianceState=='NonCompliant'] | length(@)" \
    -o tsv
}

has_active_remediation () {
  local ASSIGNMENT_ID="$1"
  # If a remediation exists and is not in a terminal state, we consider it active
  local ACTIVE
  ACTIVE=$(az policy remediation list --subscription "$SUBSCRIPTION_ID" \
    --query "[?policyAssignmentId=='$ASSIGNMENT_ID' && (provisioningState=='Accepted' || provisioningState=='InProgress')] | length(@)" \
    -o tsv)
  [ "$ACTIVE" -gt 0 ]
}

create_remediation () {
  local NAME_PREFIX="$1"
  local ASSIGNMENT_NAME="$2"

  local ASSIGNMENT_ID="/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Authorization/policyAssignments/$ASSIGNMENT_NAME"

  if has_active_remediation "$ASSIGNMENT_ID"; then
    echo "Remediation already active for $ASSIGNMENT_NAME -> skipping creation"
    return
  fi

  local REM_NAME="${NAME_PREFIX}-$(date +%s)"
  echo "Creating remediation: $REM_NAME for assignment: $ASSIGNMENT_NAME"
  az policy remediation create \
    --name "$REM_NAME" \
    --subscription "$SUBSCRIPTION_ID" \
    --policy-assignment "$ASSIGNMENT_NAME" \
    --resource-discovery-mode ExistingNonCompliant >/dev/null
}

# 1) Scan
trigger_scan
sleep 90

# 2) Stream Analytics diagnostics (DeployIfNotExists)
ASSIGNMENT_STREAM="aoss-assign-deploy-diagnostics-stream"
COUNT_STREAM=$(noncompliant_count "$ASSIGNMENT_STREAM")
echo "Stream Analytics non-compliant count: $COUNT_STREAM"
if [ "$COUNT_STREAM" -gt 0 ]; then
  create_remediation "remediate-stream-analytics" "$ASSIGNMENT_STREAM"
else
  echo "No Stream Analytics remediation needed"
fi

# 3) Storage secure transfer (Modify assignment)
ASSIGNMENT_STORAGE="aoss-assign-remediate-secure-transfer-storage"
COUNT_STORAGE=$(noncompliant_count "$ASSIGNMENT_STORAGE")
echo "Storage Accounts non-compliant count: $COUNT_STORAGE"
if [ "$COUNT_STORAGE" -gt 0 ]; then
  create_remediation "remediate-secure-transfer" "$ASSIGNMENT_STORAGE"
else
  echo "No Storage remediation needed"
fi

echo "Auto-remediation step completed."
