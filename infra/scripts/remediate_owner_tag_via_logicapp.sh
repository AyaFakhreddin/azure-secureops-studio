#!/usr/bin/env bash
set -euo pipefail

RAW_SUB="${1:-}"
RG="${2:-aoss-dev-rg-secops}"
LOGICAPP_NAME="${3:-la-owner-tag-remediation}"
TRIGGER_NAME="${4:-manual}"   # in your template it's "manual"
ASSIGNMENT_NAME="${5:-audit-owner-tag-assignment}"

if [[ -z "$RAW_SUB" ]]; then
  echo "Usage: $0 <subscriptionId or /subscriptions/id> [rg] [logicapp_name] [trigger_name] [policy_assignment_name]"
  exit 1
fi

SUBSCRIPTION_ID="${RAW_SUB##*/}"
echo "✅ Subscription: $SUBSCRIPTION_ID"
echo "✅ RG: $RG | LogicApp: $LOGICAPP_NAME | Trigger: $TRIGGER_NAME | Assignment: $ASSIGNMENT_NAME"

az account set --subscription "$SUBSCRIPTION_ID" >/dev/null

echo "🔄 Triggering Azure Policy evaluation..."
az policy state trigger-scan --subscription "$SUBSCRIPTION_ID" >/dev/null
sleep 60

echo "🔎 Getting non-compliant resources for assignment: $ASSIGNMENT_NAME ..."
RESOURCE_IDS=$(az policy state list \
  --subscription "$SUBSCRIPTION_ID" \
  --query "[?policyAssignmentName=='$ASSIGNMENT_NAME' && complianceState=='NonCompliant'].resourceId" \
  -o tsv)

if [[ -z "${RESOURCE_IDS// }" ]]; then
  echo "✅ No non-compliant resources found. Nothing to remediate."
  exit 0
fi

echo "🌐 Getting Logic App callback URL..."
CALLBACK_URL=$(az logic workflow list-callback-url \
  --subscription "$SUBSCRIPTION_ID" \
  --resource-group "$RG" \
  --name "$LOGICAPP_NAME" \
  --trigger-name "$TRIGGER_NAME" \
  --query "value" -o tsv)

if [[ -z "${CALLBACK_URL// }" ]]; then
  echo "❌ Could not retrieve callback URL. Check RG/name/trigger."
  exit 1
fi

echo "✅ Callback URL acquired."

COUNT=0
FAIL=0

while IFS= read -r RID; do
  [[ -z "${RID// }" ]] && continue
  COUNT=$((COUNT+1))
  echo "➡️  Remediating [$COUNT]: $RID"

  # Call Logic App with resourceId payload
  HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
    -X POST "$CALLBACK_URL" \
    -H "Content-Type: application/json" \
    -d "{\"resourceId\":\"$RID\"}")

  if [[ "$HTTP_CODE" == "202" || "$HTTP_CODE" == "200" ]]; then
    echo "✅ Triggered (HTTP $HTTP_CODE)"
  else
    echo "❌ Failed (HTTP $HTTP_CODE)"
    FAIL=$((FAIL+1))
  fi
done <<< "$RESOURCE_IDS"

echo "📌 Remediation calls done. total=$COUNT failed=$FAIL"

echo "🔄 Triggering another policy scan (to refresh compliance)..."
az policy state trigger-scan --subscription "$SUBSCRIPTION_ID" >/dev/null
echo "🎉 Done."
