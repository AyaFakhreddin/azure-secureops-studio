import json
import os
from typing import Any, Dict, List
import math


def compute_policy_risk(unique_noncompliant_policies: int, top_policies: List[Dict]) -> Dict[str, Any]:
    """
    Enhanced policy risk with severity weighting and exponential scaling.
    - Uses logarithmic scaling to penalize high policy counts more heavily
    - Considers frequency of violations (top policies)
    - Maximum: 40 points
    """
    n = max(0, int(unique_noncompliant_policies))
    
    if n == 0:
        return {"score": 0, "severity": "none", "details": "No policy violations"}
    
    # Logarithmic scaling: grows slower initially, faster at high counts
    # Formula: 40 * (1 - e^(-n/10))
    base_score = 40 * (1 - math.exp(-n / 10))
    
    # Frequency multiplier: if top policies show concentrated violations
    frequency_multiplier = 1.0
    if top_policies:
        top_3_records = sum(p.get("noncompliant_records", 0) for p in top_policies[:3])
        total_records = sum(p.get("noncompliant_records", 0) for p in top_policies)
        
        if total_records > 0:
            concentration = top_3_records / total_records
            # If top 3 policies represent >60% of violations, it's more critical
            if concentration > 0.6:
                frequency_multiplier = 1.2
    
    final_score = min(40, base_score * frequency_multiplier)
    
    if final_score <= 10:
        severity = "low"
    elif final_score <= 25:
        severity = "medium"
    else:
        severity = "high"
    
    return {
        "score": int(final_score),
        "severity": severity,
        "details": f"{n} unique violations, concentration factor: {frequency_multiplier:.2f}"
    }


def compute_iam_risk(drift_level: str, iam_counts: Dict[str, int]) -> Dict[str, Any]:
    """
    Enhanced IAM risk with granular role analysis and privilege sprawl detection.
    - Analyzes Owner, Contributor, and Reader counts
    - Penalizes excessive privileged accounts
    - Maximum: 35 points
    """
    drift = (drift_level or "").strip().lower()
    owners = max(0, int(iam_counts.get("owners", 0)))
    contributors = max(0, int(iam_counts.get("contributors", 0)))
    readers = max(0, int(iam_counts.get("readers", 0)))
    
    base_score = 0
    severity = "none"
    
    # Owner risk (most critical)
    if owners > 0:
        if owners == 1:
            owner_score = 5  # Acceptable - break-glass account
        elif owners <= 3:
            owner_score = 15  # Moderate concern
        elif owners <= 5:
            owner_score = 25  # High concern
        else:
            owner_score = 35  # Critical - too many privileged accounts
        
        base_score += owner_score
        severity = "critical" if owners > 5 else "high" if owners > 3 else "medium"
    
    # Contributor sprawl (secondary concern)
    if contributors > 0:
        # Logarithmic penalty for contributor sprawl
        contrib_score = min(15, 15 * (1 - math.exp(-contributors / 20)))
        base_score += contrib_score
        
        if severity == "none":
            severity = "high" if contributors > 30 else "medium" if contributors > 15 else "low"
    
    # Privilege ratio analysis
    total_privileged = owners + contributors
    if total_privileged > 0 and readers > 0:
        privilege_ratio = total_privileged / (total_privileged + readers)
        # If >50% of accounts have write access, add penalty
        if privilege_ratio > 0.5:
            base_score += 5
    
    final_score = min(35, int(base_score))
    
    details = f"Owners: {owners}, Contributors: {contributors}, Readers: {readers}"
    if owners > 5:
        details += " [CRITICAL: Excessive Owner accounts]"
    
    return {
        "score": final_score,
        "severity": severity,
        "details": details
    }


def compute_defender_risk(high: int, medium: int, low: int = 0) -> Dict[str, Any]:
    """
    Enhanced Defender risk with weighted severity and exponential penalties.
    - High severity: 20 points each (up to 5, then logarithmic)
    - Medium severity: 8 points each (up to 10, then logarithmic)
    - Low severity: 2 points each (capped contribution)
    - Maximum: 35 points
    """
    h = max(0, int(high))
    m = max(0, int(medium))
    l = max(0, int(low))
    
    if h == 0 and m == 0 and l == 0:
        return {"score": 0, "severity": "none", "details": "No Defender alerts"}
    
    # High severity: exponential impact
    if h <= 5:
        high_score = h * 20
    else:
        # After 5 high alerts, use logarithmic to avoid saturation
        high_score = 100 + (20 * math.log(h - 4))
    
    # Medium severity: moderate impact
    if m <= 10:
        medium_score = m * 8
    else:
        medium_score = 80 + (8 * math.log(m - 9))
    
    # Low severity: minimal impact
    low_score = min(10, l * 2)
    
    total_score = high_score + medium_score + low_score
    final_score = min(35, int(total_score))
    
    if h >= 5:
        severity = "critical"
    elif h >= 2 or m >= 15:
        severity = "high"
    elif h >= 1 or m >= 5:
        severity = "medium"
    else:
        severity = "low"
    
    return {
        "score": final_score,
        "severity": severity,
        "details": f"High: {h}, Medium: {m}, Low: {l}"
    }


def compute_network_risk(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    NEW: Network security risk assessment
    - Checks for NSG misconfigurations
    - Public IP exposure
    - Maximum: 15 points
    """
    network = data.get("network", {}) or {}
    
    open_ports = network.get("open_high_risk_ports", 0)
    public_ips = network.get("public_ip_count", 0)
    missing_nsgs = network.get("missing_nsg_count", 0)
    
    score = 0
    
    # Critical ports exposed (SSH, RDP, SQL)
    if open_ports > 0:
        score += min(10, open_ports * 3)
    
    # Public IP exposure
    if public_ips > 5:
        score += 3
    elif public_ips > 2:
        score += 2
    
    # Missing NSGs
    if missing_nsgs > 0:
        score += min(5, missing_nsgs * 2)
    
    final_score = min(15, score)
    
    if score == 0:
        return {"score": 0, "severity": "none", "details": "No network issues detected"}
    
    severity = "high" if final_score >= 10 else "medium" if final_score >= 5 else "low"
    
    return {
        "score": final_score,
        "severity": severity,
        "details": f"Open risk ports: {open_ports}, Public IPs: {public_ips}, Missing NSGs: {missing_nsgs}"
    }


def compute_encryption_risk(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    NEW: Encryption and data protection risk
    - Storage encryption
    - TLS/SSL configuration
    - Maximum: 10 points
    """
    encryption = data.get("encryption", {}) or {}
    
    unencrypted_storage = encryption.get("unencrypted_storage_accounts", 0)
    weak_tls = encryption.get("weak_tls_configs", 0)
    no_cmk = encryption.get("no_customer_managed_keys", 0)
    
    score = 0
    
    if unencrypted_storage > 0:
        score += 5
    
    if weak_tls > 0:
        score += 3
    
    if no_cmk > 3:  # Only penalize if significant
        score += 2
    
    final_score = min(10, score)
    
    if score == 0:
        return {"score": 0, "severity": "none", "details": "Encryption controls adequate"}
    
    severity = "high" if final_score >= 7 else "medium" if final_score >= 4 else "low"
    
    return {
        "score": final_score,
        "severity": severity,
        "details": f"Unencrypted storage: {unencrypted_storage}, Weak TLS: {weak_tls}"
    }


def compute_composite_risk_level(score: int, component_severities: List[str]) -> str:
    """
    Enhanced risk level with component severity consideration.
    """
    critical_count = component_severities.count("critical")
    high_count = component_severities.count("high")
    
    # If any component is critical, elevate the overall level
    if critical_count > 0 and score >= 50:
        return "Critical"
    
    if score >= 75:
        return "Critical"
    if score >= 60:
        return "High"
    if score >= 40:
        return "Medium-High"
    if score >= 25:
        return "Medium"
    if score >= 10:
        return "Low-Medium"
    return "Low"


def generate_risk_trends(score: int, components: Dict[str, Dict]) -> Dict[str, Any]:
    """
    Generate risk distribution and key drivers
    """
    total = sum(c["score"] for c in components.values())
    
    distribution = {}
    for name, comp in components.items():
        if total > 0:
            distribution[name] = {
                "score": comp["score"],
                "percentage": round((comp["score"] / total) * 100, 1),
                "severity": comp["severity"]
            }
    
    # Identify top risk drivers
    sorted_components = sorted(
        components.items(),
        key=lambda x: x[1]["score"],
        reverse=True
    )
    
    top_drivers = [
        {
            "component": name,
            "score": comp["score"],
            "severity": comp["severity"]
        }
        for name, comp in sorted_components[:3]
        if comp["score"] > 0
    ]
    
    return {
        "distribution": distribution,
        "top_risk_drivers": top_drivers
    }


def load_real_inputs() -> Dict[str, Any]:
    """
    Load riskscore-360/real_inputs.json robustly on Windows.
    """
    here = os.path.dirname(__file__)
    path = os.path.join(here, "real_inputs.json")

    if not os.path.exists(path):
        raise FileNotFoundError(
            f"Missing input file: {path}\n"
            f"Generate it with:\n"
            f"  python riskscore-360/collect_real_inputs.py > riskscore-360/real_inputs.json"
        )

    for enc in ("utf-8", "utf-8-sig", "utf-16", "utf-16-le", "utf-16-be"):
        try:
            with open(path, "r", encoding=enc) as f:
                return json.load(f)
        except UnicodeDecodeError:
            continue

    raise UnicodeDecodeError(
        "Unable to decode real_inputs.json with utf-8/utf-8-sig/utf-16 variants.",
        b"",
        0,
        1,
        "unknown encoding",
    )


def main() -> None:
    data = load_real_inputs()

    subscription_id = data.get("subscription_id", "unknown")
    rg = data.get("resource_group", "unknown")

    # Policy data
    policy = data.get("policy", {}) or {}
    unique_nc = policy.get("unique_noncompliant_policies", 0)
    top_policies = policy.get("top_noncompliant_policies", [])

    # IAM data
    iam_drift = data.get("iam_drift", "none")
    iam_counts = data.get("iam_counts", {}) or {}
    owner_sample = data.get("owner_principals_sample", []) or []
    contributor_sample = data.get("contributor_principals_sample", []) or []

    # Defender data
    defender = data.get("defender", {}) or {}
    defender_high = defender.get("high", 0)
    defender_medium = defender.get("medium", 0)
    defender_low = defender.get("low", 0)

    # Compute enhanced risk scores
    policy_result = compute_policy_risk(unique_nc, top_policies)
    iam_result = compute_iam_risk(iam_drift, iam_counts)
    defender_result = compute_defender_risk(defender_high, defender_medium, defender_low)
    network_result = compute_network_risk(data)
    encryption_result = compute_encryption_risk(data)

    # Aggregate components
    components = {
        "policy": policy_result,
        "iam": iam_result,
        "defender": defender_result,
        "network": network_result,
        "encryption": encryption_result
    }

    # Calculate total score (max 135, normalized to 100)
    total_raw = sum(c["score"] for c in components.values())
    max_possible = 40 + 35 + 35 + 15 + 10  # 135
    score = min(100, int((total_raw / max_possible) * 100))

    # Determine risk level with component context
    severities = [c["severity"] for c in components.values()]
    risk_lvl = compute_composite_risk_level(score, severities)

    # Generate insights
    trends = generate_risk_trends(score, components)

    result = {
        "subscription_id": subscription_id,
        "resource_group": rg,
        "risk_score": score,
        "risk_level": risk_lvl,
        "component_scores": {
            "policy_risk": policy_result["score"],
            "iam_risk": iam_result["score"],
            "defender_risk": defender_result["score"],
            "network_risk": network_result["score"],
            "encryption_risk": encryption_result["score"]
        },
        "component_details": {
            "policy": policy_result,
            "iam": iam_result,
            "defender": defender_result,
            "network": network_result,
            "encryption": encryption_result
        },
        "risk_analysis": {
            "total_raw_score": total_raw,
            "max_possible_score": max_possible,
            "normalized_score": score,
            "risk_distribution": trends["distribution"],
            "top_risk_drivers": trends["top_risk_drivers"]
        },
        "raw_inputs": {
            "policy": {
                "unique_noncompliant_policies": int(unique_nc),
                "top_noncompliant_policies": top_policies,
            },
            "iam": {
                "drift": iam_drift,
                "counts": iam_counts,
                "owner_principals_sample": owner_sample,
                "contributor_principals_sample": contributor_sample,
            },
            "defender": {
                "high": int(defender_high),
                "medium": int(defender_medium),
                "low": int(defender_low)
            },
            "network": data.get("network", {}),
            "encryption": data.get("encryption", {})
        },
    }

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()