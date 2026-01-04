import json
import os
from typing import Dict, Any, List, Tuple

import requests
from azure.identity import DefaultAzureCredential


def get_token(scope: str) -> str:
    cred = DefaultAzureCredential(exclude_interactive_browser_credential=False)
    return cred.get_token(scope).token


def arm_get(url: str, token: str) -> Dict[str, Any]:
    headers = {"Authorization": f"Bearer {token}"}
    r = requests.get(url, headers=headers, timeout=60)
    r.raise_for_status()
    return r.json()


def list_all_pages(url: str, token: str) -> List[Dict[str, Any]]:
    items: List[Dict[str, Any]] = []
    while url:
        data = arm_get(url, token)
        items.extend(data.get("value", []))
        url = data.get("nextLink")
    return items


def get_policy_noncompliance_details(subscription_id: str, rg_name: str, token: str) -> Dict[str, Any]:
    """
    Uses Azure Policy Insights policyStates query at RG scope.
    Returns:
      - unique_noncompliant_policies: count of distinct policyDefinitionId
      - noncompliant_state_records: total noncompliant policy state records (for context)
      - top_noncompliant_policies: top 5 policyDefinitionId by number of state records
    """
    url = (
        f"https://management.azure.com/subscriptions/{subscription_id}"
        f"/resourceGroups/{rg_name}"
        f"/providers/Microsoft.PolicyInsights/policyStates/latest/queryResults"
        f"?api-version=2019-10-01"
    )

    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    body = {"query": "SELECT * WHERE complianceState = 'NonCompliant'"}

    r = requests.post(url, headers=headers, json=body, timeout=60)
    r.raise_for_status()
    data = r.json()

    unique_defs = set()
    counts: Dict[str, int] = {}

    rows = data.get("value", []) or []
    for row in rows:
        pdid = row.get("policyDefinitionId")
        if not pdid:
            continue
        unique_defs.add(pdid)
        counts[pdid] = counts.get(pdid, 0) + 1

    top = sorted(counts.items(), key=lambda x: x[1], reverse=True)[:5]
    top_policies = [{"policyDefinitionId": k, "noncompliant_records": v} for k, v in top]

    return {
        "unique_noncompliant_policies": len(unique_defs),
        "noncompliant_state_records": len(rows),
        "top_noncompliant_policies": top_policies,
    }


def get_iam_drift_details(subscription_id: str, token: str) -> Dict[str, Any]:
    """
    Pull RBAC roleAssignments at subscription scope.
    Returns:
      - iam_drift: none | contributor | owner  (threshold-based)
      - iam_counts: owners / contributors
      - owner_principals_sample: up to 5 principalIds holding Owner
      - contributor_principals_sample: up to 5 principalIds holding Contributor
    """
    url = (
        f"https://management.azure.com/subscriptions/{subscription_id}"
        f"/providers/Microsoft.Authorization/roleAssignments"
        f"?api-version=2022-04-01"
    )

    role_assignments = list_all_pages(url, token)

    # Common built-in role GUIDs
    OWNER_GUID = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635"
    CONTRIBUTOR_GUID = "b24988ac-6180-42a0-ab88-20f7382dd24c"

    owners = 0
    contributors = 0
    owner_principals: List[Dict[str, Any]] = []
    contributor_principals: List[Dict[str, Any]] = []

    for ra in role_assignments:
        props = ra.get("properties", {}) or {}
        rd = (props.get("roleDefinitionId") or "").lower()

        principal_id = props.get("principalId")
        principal_type = props.get("principalType")

        if rd.endswith(OWNER_GUID):
            owners += 1
            if principal_id and len(owner_principals) < 5:
                owner_principals.append({"principalId": principal_id, "principalType": principal_type})
        elif rd.endswith(CONTRIBUTOR_GUID):
            contributors += 1
            if principal_id and len(contributor_principals) < 5:
                contributor_principals.append({"principalId": principal_id, "principalType": principal_type})

    # Threshold-based drift logic (fast + defensible for your report)
    # Typical baseline in small environments is <=2 owners
    drift = "none"
    if owners > 2:
        drift = "owner"
    elif contributors > 5:
        drift = "contributor"

    return {
        "iam_drift": drift,
        "iam_counts": {"owners": owners, "contributors": contributors},
        "owner_principals_sample": owner_principals,
        "contributor_principals_sample": contributor_principals,
    }


def get_defender_findings_counts(subscription_id: str, rg_name: str, token: str) -> Dict[str, int]:
    """
    Pull Microsoft Defender for Cloud assessments at RG scope.
    Count unhealthy assessments by severity (high/medium).
    """
    url = (
        f"https://management.azure.com/subscriptions/{subscription_id}"
        f"/resourceGroups/{rg_name}"
        f"/providers/Microsoft.Security/assessments"
        f"?api-version=2020-01-01"
    )
    assessments = list_all_pages(url, token)

    high = 0
    medium = 0

    for a in assessments:
        props = a.get("properties", {}) or {}
        status = props.get("status", {}) or {}
        if (status.get("code") or "").lower() != "unhealthy":
            continue

        meta = props.get("metadata", {}) or {}
        sev = (meta.get("severity") or "").lower()

        if sev == "high":
            high += 1
        elif sev == "medium":
            medium += 1

    return {"high": high, "medium": medium}


def main():
    config_path = os.path.join(os.path.dirname(__file__), "config.json")
    if not os.path.exists(config_path):
        raise FileNotFoundError(
            f"Missing config.json at {config_path}\n"
            f"Create riskscore-360/config.json like:\n"
            f'{{"subscription_id":"<SUB_ID>","resource_group":"<RG_NAME>"}}'
        )

    with open(config_path, "r", encoding="utf-8-sig") as f:
        cfg = json.load(f)

    subscription_id = cfg["subscription_id"]
    rg_name = cfg["resource_group"]

    token = get_token("https://management.azure.com/.default")

    policy_details = get_policy_noncompliance_details(subscription_id, rg_name, token)
    iam_details = get_iam_drift_details(subscription_id, token)
    defender_counts = get_defender_findings_counts(subscription_id, rg_name, token)

    out = {
        "subscription_id": subscription_id,
        "resource_group": rg_name,
        "policy": policy_details,
        **iam_details,
        "defender": defender_counts,
    }

    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
