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

trigger_scan () {
  echo "Triggering Azure Policy evaluation..."
  az policy state trigger-scan --subscription "$SUBSCRIPTION_ID" >/dev/null
}

noncompliant_count () {
  local assignment_name="$1"
  az policy state list \
    --subscription "$SUBSCRIPTION_ID" \
    --query "[?policyAssignmentName=='$assignment_name' && complianceState=='NonCompliant'] | length(@)" \
    -o tsv
}

create_remediation () {
  local remediation_name="$1"
  echo "Creating remediation: $remediation_name"

  az policy remediation create \
    --name "$remediation_name" \
    --subscription "$SUBSCRIPTION_ID" \
    --policy-assignment "$ASSIGNMENT_NAME" \
    --resource-discovery-mode ExistingNonCompliant \
    --location "$LOCATION" \
    -o jsonc
}

wait_remediation () {
  local remediation_name="$1"

  echo "Waiting for completion..."
  for i in $(seq 1 40); do
    state="$(az policy remediation show --subscription "$SUBSCRIPTION_ID" --name "$remediation_name" --query provisioningState -o tsv || true)"
    echo "[$i/40] provisioningState=$state"
    if [ "$state" = "Succeeded" ] || [ "$state" = "Failed" ] || [ "$state" = "Canceled" ]; then
      break
    fi
    sleep 15
  done

  echo "Final remediation object:"
  az policy remediation show --subscription "$SUBSCRIPTION_ID" --name "$remediation_name" -o jsonc || true

  echo "Deployment details per resource:"
  az policy remediation deployment list --subscription "$SUBSCRIPTION_ID" --name "$remediation_name" -o table || true

  if [ "$state" != "Succeeded" ]; then
    echo "ERROR: remediation ended with state=$state"
    exit 1
  fi
}

# 1) scan + wait (policy states take time)
trigger_scan
sleep 120

# 2) detect noncompliant
COUNT="$(noncompliant_count "$ASSIGNMENT_NAME")"
echo "Non-compliant storage accounts (policy states): $COUNT"

if [ "$COUNT" -eq 0 ]; then
  echo "No remediation needed."
  exit 0
fi

REM_NAME="remediate-storage-diag-$(date +%s)"
create_remediation "$REM_NAME"
wait_remediation "$REM_NAME"

echo "Storage diagnostics remediation completed successfully."
