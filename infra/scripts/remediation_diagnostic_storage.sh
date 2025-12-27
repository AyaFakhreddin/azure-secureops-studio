#!/usr/bin/env bash
set -euo pipefail

RAW_SUB="${1:-}"
if [[ -z "$RAW_SUB" ]]; then
  echo "Usage: $0 <subscriptionResourceIdOrGuid>"
  exit 1
fi

SUBSCRIPTION_ID="${RAW_SUB##*/}"
ASSIGNMENT_NAME="deploy-storage-diagnostics-assignment"
LOCATION_FILTER="francecentral"   # change if needed

echo "Using subscription: $SUBSCRIPTION_ID"
echo "Assignment: $ASSIGNMENT_NAME"
echo "Location: $LOCATION_FILTER"

trigger_scan() {
  echo "Triggering Azure Policy evaluation..."
  az policy state trigger-scan --subscription "$SUBSCRIPTION_ID" >/dev/null
}

noncompliant_count() {
  # IMPORTANT: policy states take time; query by assignment name.
  az policy state list \
    --subscription "$SUBSCRIPTION_ID" \
    --query "[?policyAssignmentName=='$ASSIGNMENT_NAME' && complianceState=='NonCompliant'] | length(@)" \
    -o tsv
}

create_remediation() {
  local REM_NAME="remediate-storage-diag-$(date +%s)"
  echo "Creating remediation: $REM_NAME"

  az policy remediation create \
    --name "$REM_NAME" \
    --subscription "$SUBSCRIPTION_ID" \
    --policy-assignment "$ASSIGNMENT_NAME" \
    --resource-discovery-mode ExistingNonCompliant \
    --location-filters "$LOCATION_FILTER" >/dev/null

  echo "Remediation created: $REM_NAME"
  echo "$REM_NAME"
}

wait_remediation() {
  local REM_NAME="$1"
  echo "Waiting for completion..."

  for i in $(seq 1 40); do
    STATE="$(az policy remediation show --subscription "$SUBSCRIPTION_ID" --name "$REM_NAME" --query provisioningState -o tsv)"
    echo "[$i/40] provisioningState=$STATE"
    if [[ "$STATE" == "Succeeded" || "$STATE" == "Failed" || "$STATE" == "Canceled" ]]; then
      break
    fi
    sleep 15
  done

  echo "Remediation status:"
  az policy remediation show --subscription "$SUBSCRIPTION_ID" --name "$REM_NAME" -o jsonc

  echo ""
  echo "Deployment details per resource:"
  az policy remediation deployment list \
    --subscription "$SUBSCRIPTION_ID" \
    --name "$REM_NAME" \
    --query "[].{resource:remediatedResourceId,status:status,code:error.code,msg:error.message}" \
    -o table || true
}

# 1) Scan
trigger_scan

# 2) Wait until policy states are likely ready (Azure Policy is slow)
sleep 120

# 3) Count
COUNT="$(noncompliant_count)"
echo "Non-compliant storage accounts (policy states): $COUNT"

# If policy states still show 0 but portal shows resources to remediate,
# it’s usually propagation delay. We retry a few times.
if [[ "$COUNT" == "0" ]]; then
  echo "States not ready yet. Retrying (up to 3 times)..."
  for _ in 1 2 3; do
    sleep 60
    COUNT="$(noncompliant_count)"
    echo "Non-compliant storage accounts (retry): $COUNT"
    [[ "$COUNT" != "0" ]] && break
  done
fi

if [[ "$COUNT" -gt 0 ]]; then
  REM_NAME="$(create_remediation)"
  wait_remediation "$REM_NAME"
else
  echo "No remediation needed (per policy states)."
  echo "If Portal still shows 'Resources to remediate: 3', wait a few minutes then re-run."
fi
