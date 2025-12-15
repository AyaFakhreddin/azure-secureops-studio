#!/bin/bash
set -e

SUBID="${1##*/}"

ASSIGNMENT_NAME="deploy-storage-diagnostics-assignment"

echo "Triggering policy scan..."
az policy state trigger-scan --subscription "$SUBID"
sleep 60

COUNT=$(az policy state list \
  --subscription "$SUBID" \
  --query "[?policyAssignmentName=='$ASSIGNMENT_NAME' && complianceState=='NonCompliant'] | length(@)" \
  -o tsv)

echo "Non-compliant storage accounts: $COUNT"

if [ "$COUNT" -gt 0 ]; then
  echo "Creating remediation..."
  az policy remediation create \
    --name "remediate-storage-diag-$(date +%s)" \
    --subscription "$SUBID" \
    --policy-assignment "$ASSIGNMENT_NAME" \
    --resource-discovery-mode ExistingNonCompliant
else
  echo "No remediation needed"
fi
