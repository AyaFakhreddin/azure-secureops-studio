import json
import os
from typing import Dict, Any, List, Set
from concurrent.futures import ThreadPoolExecutor, as_completed
import sys

import requests
from azure.identity import DefaultAzureCredential


def get_token(scope: str) -> str:
    """Get Azure authentication token"""
    cred = DefaultAzureCredential(exclude_interactive_browser_credential=False)
    return cred.get_token(scope).token


def arm_get(url: str, token: str, timeout: int = 60) -> Dict[str, Any]:
    """Execute GET request to Azure Resource Manager"""
    headers = {"Authorization": f"Bearer {token}"}
    r = requests.get(url, headers=headers, timeout=timeout)
    r.raise_for_status()
    return r.json()


def arm_post(url: str, token: str, body: Dict[str, Any], timeout: int = 60) -> Dict[str, Any]:
    """Execute POST request to Azure Resource Manager"""
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    r = requests.post(url, headers=headers, json=body, timeout=timeout)
    r.raise_for_status()
    return r.json()


def list_all_pages(url: str, token: str) -> List[Dict[str, Any]]:
    """Paginate through Azure API results"""
    items: List[Dict[str, Any]] = []
    while url:
        data = arm_get(url, token)
        items.extend(data.get("value", []))
        url = data.get("nextLink")
    return items


def get_policy_noncompliance_details(subscription_id: str, rg_name: str, token: str) -> Dict[str, Any]:
    """
    Enhanced policy compliance analysis - BACKWARD COMPATIBLE
    Returns both old and new fields for compatibility
    """
    url = (
        f"https://management.azure.com/subscriptions/{subscription_id}"
        f"/resourceGroups/{rg_name}"
        f"/providers/Microsoft.PolicyInsights/policyStates/latest/queryResults"
        f"?api-version=2019-10-01"
    )

    body = {"query": "SELECT * WHERE complianceState = 'NonCompliant'"}
    
    try:
        data = arm_post(url, token, body)
    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 404:
            # Resource group might not have policy states
            return {
                "unique_noncompliant_policies": 0,
                "noncompliant_state_records": 0,
                "top_noncompliant_policies": [],
            }
        raise

    unique_defs: Set[str] = set()
    counts: Dict[str, int] = {}
    policy_names: Dict[str, str] = {}

    rows = data.get("value", []) or []
    for row in rows:
        pdid = row.get("policyDefinitionId")
        if not pdid:
            continue
        
        unique_defs.add(pdid)
        counts[pdid] = counts.get(pdid, 0) + 1
        
        # Store policy name for enhanced reporting
        if pdid not in policy_names:
            policy_names[pdid] = row.get("policyDefinitionName", "Unknown")

    # Top 10 for new system (but keep top 5 logic for compatibility)
    top_sorted = sorted(counts.items(), key=lambda x: x[1], reverse=True)
    
    # OLD FORMAT (top 5, no policy names) - for backward compatibility
    top_5 = [{"policyDefinitionId": k, "noncompliant_records": v} for k, v in top_sorted[:5]]
    
    # NEW FORMAT (top 10, with policy names) - for enhanced system
    top_10 = [
        {
            "policyDefinitionId": k,
            "policyName": policy_names.get(k, "Unknown"),
            "noncompliant_records": v
        }
        for k, v in top_sorted[:10]
    ]

    return {
        # OLD FIELDS (required for backward compatibility)
        "unique_noncompliant_policies": len(unique_defs),
        "noncompliant_state_records": len(rows),
        "top_noncompliant_policies": top_10,  # Enhanced but compatible
    }


def get_iam_drift_details(subscription_id: str, token: str) -> Dict[str, Any]:
    """
    Enhanced IAM/RBAC analysis - BACKWARD COMPATIBLE
    Returns both old and new fields
    """
    url = (
        f"https://management.azure.com/subscriptions/{subscription_id}"
        f"/providers/Microsoft.Authorization/roleAssignments"
        f"?api-version=2022-04-01"
    )

    role_assignments = list_all_pages(url, token)

    # Built-in role GUIDs
    OWNER_GUID = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635"
    CONTRIBUTOR_GUID = "b24988ac-6180-42a0-ab88-20f7382dd24c"
    READER_GUID = "acdd72a7-3385-48ef-bd42-f606fba81ae7"

    owners = 0
    contributors = 0
    readers = 0
    custom_roles = 0
    
    owner_principals: List[Dict[str, Any]] = []
    contributor_principals: List[Dict[str, Any]] = []
    
    principal_type_counts = {"User": 0, "ServicePrincipal": 0, "Group": 0, "Other": 0}
    
    # Track unique principals to avoid double counting
    unique_owner_principals: Set[str] = set()
    unique_contributor_principals: Set[str] = set()

    for ra in role_assignments:
        props = ra.get("properties", {}) or {}
        rd = (props.get("roleDefinitionId") or "").lower()
        
        principal_id = props.get("principalId")
        principal_type = props.get("principalType", "Other")
        scope = props.get("scope", "")

        # Count principal types
        principal_type_counts[principal_type] = principal_type_counts.get(principal_type, 0) + 1

        if rd.endswith(OWNER_GUID):
            owners += 1
            if principal_id and principal_id not in unique_owner_principals:
                unique_owner_principals.add(principal_id)
                # Keep first 10 for enhanced, but compatible with old system expecting 5
                if len(owner_principals) < 10:
                    owner_principals.append({
                        "principalId": principal_id,
                        "principalType": principal_type,
                        "scope": scope  # NEW field, ignored by old system
                    })
        elif rd.endswith(CONTRIBUTOR_GUID):
            contributors += 1
            if principal_id and principal_id not in unique_contributor_principals:
                unique_contributor_principals.add(principal_id)
                if len(contributor_principals) < 10:
                    contributor_principals.append({
                        "principalId": principal_id,
                        "principalType": principal_type,
                        "scope": scope  # NEW field
                    })
        elif rd.endswith(READER_GUID):
            readers += 1
        else:
            custom_roles += 1

    # Threshold-based drift logic (compatible with old system)
    drift = "none"
    if owners > 2:
        drift = "owner"
    elif contributors > 5:
        drift = "contributor"

    return {
        # OLD FIELDS (required for backward compatibility)
        "iam_drift": drift,
        "iam_counts": {
            "owners": owners,
            "contributors": contributors,
            # NEW fields below (ignored by old system)
            "readers": readers,
            "custom_roles": custom_roles
        },
        "owner_principals_sample": owner_principals,
        "contributor_principals_sample": contributor_principals,
        # NEW field (ignored by old system)
        "principal_type_breakdown": principal_type_counts
    }


def get_defender_findings_counts(subscription_id: str, rg_name: str, token: str) -> Dict[str, Any]:
    """
    Enhanced Defender assessment - BACKWARD COMPATIBLE
    Returns old format (high/medium) plus new fields (low, categories)
    """
    url = (
        f"https://management.azure.com/subscriptions/{subscription_id}"
        f"/resourceGroups/{rg_name}"
        f"/providers/Microsoft.Security/assessments"
        f"?api-version=2020-01-01"
    )
    
    try:
        assessments = list_all_pages(url, token)
    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 404:
            # OLD FORMAT for backward compatibility
            return {"high": 0, "medium": 0}
        raise

    high = 0
    medium = 0
    low = 0  # NEW field
    categories: Dict[str, int] = {}  # NEW field

    for a in assessments:
        props = a.get("properties", {}) or {}
        status = props.get("status", {}) or {}
        
        if (status.get("code") or "").lower() != "unhealthy":
            continue

        meta = props.get("metadata", {}) or {}
        sev = (meta.get("severity") or "").lower()
        category = meta.get("category", "Other")

        # Count by severity
        if sev == "high":
            high += 1
        elif sev == "medium":
            medium += 1
        elif sev == "low":
            low += 1

        # Count by category (NEW field)
        categories[category] = categories.get(category, 0) + 1

    # Return both old and new format
    result = {
        # OLD FIELDS (required)
        "high": high,
        "medium": medium,
    }
    
    # NEW FIELDS (only add if there's data, for cleaner output)
    if low > 0:
        result["low"] = low
    if categories:
        result["categories"] = categories
    if high + medium + low > 0:
        result["total_unhealthy"] = high + medium + low
    
    return result


def get_network_security_data(subscription_id: str, rg_name: str, token: str) -> Dict[str, Any]:
    """
    NEW: Analyze network security configuration
    Returns empty dict on error for backward compatibility
    """
    try:
        # Get all NSGs
        nsg_url = (
            f"https://management.azure.com/subscriptions/{subscription_id}"
            f"/resourceGroups/{rg_name}"
            f"/providers/Microsoft.Network/networkSecurityGroups"
            f"?api-version=2023-05-01"
        )
        nsgs = list_all_pages(nsg_url, token)

        # Get all NICs
        nic_url = (
            f"https://management.azure.com/subscriptions/{subscription_id}"
            f"/resourceGroups/{rg_name}"
            f"/providers/Microsoft.Network/networkInterfaces"
            f"?api-version=2023-05-01"
        )
        nics = list_all_pages(nic_url, token)

        # Get public IPs
        pip_url = (
            f"https://management.azure.com/subscriptions/{subscription_id}"
            f"/resourceGroups/{rg_name}"
            f"/providers/Microsoft.Network/publicIPAddresses"
            f"?api-version=2023-05-01"
        )
        public_ips = list_all_pages(pip_url, token)

        # High-risk ports
        HIGH_RISK_PORTS = {22, 3389, 1433, 3306, 5432, 27017, 6379, 9200, 5601}
        
        open_high_risk_ports = 0
        
        for nsg in nsgs:
            props = nsg.get("properties", {}) or {}
            security_rules = props.get("securityRules", []) or []
            
            for rule in security_rules:
                rule_props = rule.get("properties", {}) or {}
                
                if (rule_props.get("direction") == "Inbound" and
                    rule_props.get("access") == "Allow"):
                    
                    source = rule_props.get("sourceAddressPrefix", "")
                    if source in ["*", "Internet", "0.0.0.0/0"]:
                        dest_port = rule_props.get("destinationPortRange", "")
                        if dest_port == "*":
                            open_high_risk_ports += len(HIGH_RISK_PORTS)
                        else:
                            try:
                                port = int(dest_port)
                                if port in HIGH_RISK_PORTS:
                                    open_high_risk_ports += 1
                            except (ValueError, TypeError):
                                pass

        # Count NICs without NSGs
        nics_without_nsg = sum(1 for nic in nics 
                               if not nic.get("properties", {}).get("networkSecurityGroup"))

        return {
            "open_high_risk_ports": open_high_risk_ports,
            "public_ip_count": len(public_ips),
            "missing_nsg_count": nics_without_nsg,
            "total_nsgs": len(nsgs),
            "total_nics": len(nics),
        }
    except Exception as e:
        print(f"Warning: Network data collection failed: {e}", file=sys.stderr)
        return {}


def get_encryption_data(subscription_id: str, rg_name: str, token: str) -> Dict[str, Any]:
    """
    NEW: Analyze encryption and data protection
    Returns empty dict on error for backward compatibility
    """
    try:
        storage_url = (
            f"https://management.azure.com/subscriptions/{subscription_id}"
            f"/resourceGroups/{rg_name}"
            f"/providers/Microsoft.Storage/storageAccounts"
            f"?api-version=2023-01-01"
        )
        storage_accounts = list_all_pages(storage_url, token)

        unencrypted_storage = 0
        weak_tls = 0
        no_cmk = 0
        https_only_violations = 0

        for sa in storage_accounts:
            props = sa.get("properties", {}) or {}
            
            # Check encryption
            encryption = props.get("encryption", {})
            if not encryption or not encryption.get("services", {}).get("blob", {}).get("enabled"):
                unencrypted_storage += 1
            
            # Check for customer-managed keys
            if encryption.get("keySource") != "Microsoft.Keyvault":
                no_cmk += 1
            
            # Check TLS version
            min_tls = props.get("minimumTlsVersion")
            if not min_tls or min_tls < "TLS1_2":
                weak_tls += 1
            
            # Check HTTPS enforcement
            if not props.get("supportsHttpsTrafficOnly", True):
                https_only_violations += 1

        return {
            "unencrypted_storage_accounts": unencrypted_storage,
            "weak_tls_configs": weak_tls,
            "no_customer_managed_keys": no_cmk,
            "https_only_violations": https_only_violations,
            "total_storage_accounts": len(storage_accounts)
        }
    except Exception as e:
        print(f"Warning: Encryption data collection failed: {e}", file=sys.stderr)
        return {}


def get_compliance_summary(subscription_id: str, token: str) -> Dict[str, Any]:
    """
    NEW: Regulatory compliance summary
    Returns empty dict on error for backward compatibility
    """
    try:
        url = (
            f"https://management.azure.com/subscriptions/{subscription_id}"
            f"/providers/Microsoft.Security/regulatoryComplianceStandards"
            f"?api-version=2019-01-01-preview"
        )
        standards = list_all_pages(url, token)

        compliance_scores = {}
        for standard in standards:
            name = standard.get("name", "Unknown")
            props = standard.get("properties", {}) or {}
            passed = props.get("passedControls", 0)
            failed = props.get("failedControls", 0)
            total = passed + failed
            
            if total > 0:
                compliance_scores[name] = {
                    "passed": passed,
                    "failed": failed,
                    "percentage": round((passed / total) * 100, 1)
                }

        return {
            "standards_tracked": len(standards),
            "compliance_scores": compliance_scores
        }
    except Exception as e:
        print(f"Warning: Compliance data collection failed: {e}", file=sys.stderr)
        return {}


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

    print(f"Collecting security data...", file=sys.stderr)
    print(f"Subscription: {subscription_id}", file=sys.stderr)
    print(f"Resource Group: {rg_name}", file=sys.stderr)
    print("", file=sys.stderr)

    token = get_token("https://management.azure.com/.default")

    # Collect core data (required for backward compatibility)
    policy_details = get_policy_noncompliance_details(subscription_id, rg_name, token)
    iam_details = get_iam_drift_details(subscription_id, token)
    defender_counts = get_defender_findings_counts(subscription_id, rg_name, token)

    # Collect enhanced data (NEW - fails gracefully if not available)
    network_data = get_network_security_data(subscription_id, rg_name, token)
    encryption_data = get_encryption_data(subscription_id, rg_name, token)
    compliance_data = get_compliance_summary(subscription_id, token)

    # Build output in BACKWARD COMPATIBLE format
    out = {
        # OLD FORMAT (required fields)
        "subscription_id": subscription_id,
        "resource_group": rg_name,
        "policy": policy_details,
        **iam_details,  # Spreads: iam_drift, iam_counts, owner_principals_sample, contributor_principals_sample
        "defender": defender_counts,
    }

    # Add NEW fields only if they have data (for cleaner output)
    if network_data:
        out["network"] = network_data
    if encryption_data:
        out["encryption"] = encryption_data
    if compliance_data:
        out["compliance"] = compliance_data

    # Output JSON to stdout (for piping to file)
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()