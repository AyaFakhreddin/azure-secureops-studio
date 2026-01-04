# riskscore-360/generate_report_pdf.py
# Generates a user-facing PDF report from reports/riskscore_real.json
# Output: reports/secureops_riskscore_report.pdf

import json
import os
from datetime import datetime, timezone
from typing import Any, Dict, List

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.lib.colors import HexColor
from reportlab.pdfgen import canvas


# ----------------------------
# Helpers: encoding + layout
# ----------------------------

def safe_load_json(path: str) -> dict:
    for enc in ("utf-8", "utf-8-sig", "utf-16", "utf-16-le", "utf-16-be"):
        try:
            with open(path, "r", encoding=enc) as f:
                return json.load(f)
        except UnicodeDecodeError:
            continue
    raise UnicodeDecodeError(
        "Unable to decode JSON with utf-8/utf-8-sig/utf-16 variants.",
        b"",
        0,
        1,
        "unknown encoding",
    )


def ensure_space(c: canvas.Canvas, y: float, needed: float = 4.0 * cm) -> float:
    if y < needed:
        c.showPage()
        return A4[1] - 3.0 * cm
    return y


def wrap_text(c: canvas.Canvas, text: str, max_width: float, font_name: str, font_size: int) -> List[str]:
    words = (text or "").split()
    if not words:
        return [""]

    lines: List[str] = []
    current = ""
    for w in words:
        test = (current + " " + w).strip()
        if c.stringWidth(test, font_name, font_size) <= max_width:
            current = test
        else:
            if current:
                lines.append(current)
            current = w
    if current:
        lines.append(current)
    return lines


def draw_wrapped_text(
    c: canvas.Canvas,
    x: float,
    y: float,
    text: str,
    max_width: float,
    font_name: str = "Helvetica",
    font_size: int = 10,
    leading: int = 14,
) -> float:
    c.setFont(font_name, font_size)
    for line in wrap_text(c, text, max_width, font_name, font_size):
        c.drawString(x, y, line)
        y -= leading
    return y


def draw_section_title(c: canvas.Canvas, x: float, y: float, title: str) -> float:
    y = ensure_space(c, y, 3.0 * cm)
    c.setFillColor(HexColor("#1a1a1a"))
    c.setFont("Helvetica-Bold", 14)
    c.drawString(x, y, title)
    c.setFillColor(HexColor("#000000"))
    return y - 20


def draw_key_value(
    c: canvas.Canvas,
    x: float,
    y: float,
    key: str,
    value: str,
    max_width: float,
    key_width: float = 4.5 * cm
) -> float:
    y = ensure_space(c, y, 2.0 * cm)
    c.setFont("Helvetica-Bold", 10)
    c.drawString(x, y, f"{key}:")
    value_x = x + key_width
    value_w = max_width - key_width
    y = draw_wrapped_text(c, value_x, y, str(value), value_w, "Helvetica", 10, leading=13)
    return y - 4


def truncate_text(text: str, max_len: int = 90) -> str:
    t = str(text or "")
    if len(t) <= max_len:
        return t
    keep = max_len - 3
    left = keep // 2
    right = keep - left
    return f"{t[:left]}...{t[-right:]}"


def draw_table(
    c: canvas.Canvas,
    x: float,
    y: float,
    headers: List[str],
    rows: List[List[str]],
    col_widths: List[float],
    font_size: int = 9,
) -> float:
    padding = 4
    header_h = 18

    y = ensure_space(c, y, 4.0 * cm)

    # Header bg
    c.setFillColor(HexColor("#f0f0f0"))
    c.rect(x, y - header_h + 4, sum(col_widths), header_h, fill=1, stroke=0)
    c.setFillColor(HexColor("#000000"))

    # Headers
    c.setFont("Helvetica-Bold", 10)
    curx = x + padding
    for i, h in enumerate(headers):
        c.drawString(curx, y - 12, h)
        curx += col_widths[i]
    y -= header_h

    # Rows
    c.setFont("Helvetica", font_size)
    for row in rows:
        y = ensure_space(c, y, 3.0 * cm)

        wrapped_cells: List[List[str]] = []
        max_lines = 1

        for i, cell in enumerate(row):
            w = col_widths[i] - 2 * padding
            lines = wrap_text(c, str(cell), w, "Helvetica", font_size)
            wrapped_cells.append(lines)
            max_lines = max(max_lines, len(lines))

        line_h = font_size + 3
        for li in range(max_lines):
            curx = x + padding
            for ci, lines in enumerate(wrapped_cells):
                if li < len(lines):
                    c.drawString(curx, y - 10 - li * line_h, lines[li])
                curx += col_widths[ci]

        y -= max_lines * line_h + 8

    return y - 8


# ----------------------------
# Main
# ----------------------------

def main() -> None:
    repo_root = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
    input_json = os.path.join(repo_root, "reports", "riskscore_real.json")
    output_pdf = os.path.join(repo_root, "reports", "secureops_riskscore_report3.pdf")

    if not os.path.exists(input_json):
        raise FileNotFoundError(
            f"Missing {input_json}\n"
            f"Generate it with:\n"
            f"  python riskscore-360/compute_score.py > reports/riskscore_real.json"
        )

    data: Dict[str, Any] = safe_load_json(input_json)

    sub_id = data.get("subscription_id", "unknown")
    rg = data.get("resource_group", "unknown")
    score = data.get("risk_score", "N/A")
    level = data.get("risk_level", "N/A")

    # NEW: component_scores (preferred), fallback to legacy flat keys
    comp = data.get("component_scores", {}) or {}
    policy_risk = comp.get("policy_risk", data.get("policy_risk", 0))
    iam_risk = comp.get("iam_risk", data.get("iam_risk", 0))
    defender_risk = comp.get("defender_risk", data.get("defender_risk", 0))
    network_risk = comp.get("network_risk", data.get("network_risk", 0))
    encryption_risk = comp.get("encryption_risk", data.get("encryption_risk", 0))

    # Risk analysis (optional)
    ra = data.get("risk_analysis", {}) or {}
    total_raw = ra.get("total_raw_score", None)
    max_possible = ra.get("max_possible_score", None)
    top_drivers = (ra.get("top_risk_drivers") or []) if isinstance(ra, dict) else []

    raw = data.get("raw_inputs", {}) or {}

    policy_raw = raw.get("policy", {}) or {}
    unique_nc = policy_raw.get("unique_noncompliant_policies", 0)
    top_policies = policy_raw.get("top_noncompliant_policies", []) or []

    iam_raw = raw.get("iam", {}) or {}
    iam_drift = iam_raw.get("drift", "none")
    iam_counts = iam_raw.get("counts", {}) or {}
    owners = iam_counts.get("owners", "N/A")
    contributors = iam_counts.get("contributors", "N/A")
    readers = iam_counts.get("readers", "N/A")
    owner_sample = iam_raw.get("owner_principals_sample", []) or []
    contrib_sample = iam_raw.get("contributor_principals_sample", []) or []

    defender_raw = raw.get("defender", {}) or {}
    high = defender_raw.get("high", 0)
    medium = defender_raw.get("medium", 0)
    low = defender_raw.get("low", 0)

    network_raw = raw.get("network", {}) or {}
    open_ports = network_raw.get("open_high_risk_ports", 0)
    public_ips = network_raw.get("public_ip_count", 0)
    missing_nsg = network_raw.get("missing_nsg_count", 0)

    enc_raw = raw.get("encryption", {}) or {}
    unencrypted = enc_raw.get("unencrypted_storage_accounts", 0)
    weak_tls = enc_raw.get("weak_tls_configs", 0)

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    c = canvas.Canvas(output_pdf, pagesize=A4)
    width, height = A4
    margin = 2.5 * cm
    x = margin
    y = height - margin
    max_width = width - 2 * margin

    # Title
    c.setFont("Helvetica-Bold", 20)
    c.drawString(x, y, "SecureOps RiskScore 360")
    y -= 24
    c.setFont("Helvetica", 16)
    c.drawString(x, y, "Security Assessment Report")
    y -= 32

    # Metadata
    y = draw_key_value(c, x, y, "Generated", now, max_width)
    y = draw_key_value(c, x, y, "Subscription", truncate_text(sub_id, 70), max_width)
    y = draw_key_value(c, x, y, "Resource Group", str(rg), max_width)
    y -= 10

    # Executive summary
    y = draw_section_title(c, x, y, "1. Executive Summary")

    # Risk score box
    box_w = 6 * cm
    box_h = 2.5 * cm

    level_str = str(level).upper()
    if "CRITICAL" in level_str:
        box_color = HexColor("#b71c1c")
    elif "HIGH" in level_str:
        box_color = HexColor("#d32f2f")
    elif "MEDIUM" in level_str:
        box_color = HexColor("#f57c00")
    else:
        box_color = HexColor("#388e3c")

    c.setFillColor(box_color)
    c.rect(x, y - box_h, box_w, box_h, fill=1, stroke=0)
    c.setFillColor(HexColor("#ffffff"))
    c.setFont("Helvetica-Bold", 40)
    c.drawString(x + 1.0 * cm, y - 1.6 * cm, str(score))
    c.setFont("Helvetica-Bold", 12)
    c.drawString(x + 0.5 * cm, y - 2.2 * cm, f"Risk Level: {level}")
    c.setFillColor(HexColor("#000000"))
    y -= box_h + 14

    summary = (
        "This report consolidates governance compliance (Azure Policy), identity governance (RBAC/IAM), "
        "Defender for Cloud posture, and selected exposure controls (network & encryption) into a normalized "
        "risk score to support remediation prioritization."
    )
    y = draw_wrapped_text(c, x, y, summary, max_width, "Helvetica", 10, leading=13)
    y -= 8

    # Top risk drivers (if provided)
    if top_drivers:
        y = ensure_space(c, y, 4.0 * cm)
        c.setFont("Helvetica-Bold", 11)
        c.drawString(x, y, "Top Risk Drivers:")
        y -= 16
        c.setFont("Helvetica", 10)
        for d in top_drivers[:3]:
            comp_name = str(d.get("component", "unknown")).upper()
            sc = d.get("score", 0)
            sev = d.get("severity", "n/a")
            c.drawString(x + 0.4 * cm, y, f"- {comp_name}: {sc} points ({sev})")
            y -= 14
        y -= 4

    # Score breakdown
    y = draw_section_title(c, x, y, "2. Score Breakdown")

    headers = ["Component", "Value", "Evidence (Real Inputs)"]
    rows = [
        ["Policy", str(policy_risk), f"{unique_nc} unique non-compliant policies"],
        ["IAM", str(iam_risk), f"Drift: {iam_drift} | Owners: {owners} | Contributors: {contributors} | Readers: {readers}"],
        ["Defender", str(defender_risk), f"Unhealthy: High={high}, Medium={medium}, Low={low}"],
        ["Network", str(network_risk), f"Open risky ports: {open_ports} | Public IPs: {public_ips} | Missing NSG: {missing_nsg}"],
        ["Encryption", str(encryption_risk), f"Unencrypted storage: {unencrypted} | Weak TLS: {weak_tls}"],
    ]
    if total_raw is not None and max_possible is not None:
        rows.append(["Total (Normalized)", str(score), f"Raw: {total_raw} / {max_possible} | Level: {level}"])
    else:
        rows.append(["Total", str(score), f"Level: {level}"])

    col_widths = [3.0 * cm, 2.2 * cm, max_width - 5.2 * cm]
    y = draw_table(c, x, y, headers, rows, col_widths)
    y -= 6

    # Recommended actions
    y = draw_section_title(c, x, y, "3. Recommended Actions (Prioritized)")

    actions: List[str] = []
    if int(unique_nc) > 0:
        actions.append(
            f"Remediate {unique_nc} non-compliant Azure policies in RG '{rg}'. "
            "Start with the highest-frequency policies listed in the appendix."
        )
    if str(iam_drift).lower() in ("owner", "contributor") or (isinstance(owners, int) and owners > 2):
        actions.append(
            f"Reduce privileged sprawl: review RBAC assignments. Current counts -> Owners={owners}, Contributors={contributors}. "
            "Keep Owner role for break-glass/admin accounts only."
        )
    if int(high) + int(medium) + int(low) > 0:
        actions.append(
            f"Address Defender for Cloud unhealthy assessments: High={high}, Medium={medium}, Low={low}. "
            "Prioritize High severity first."
        )
    if int(open_ports) > 0 or int(public_ips) > 2 or int(missing_nsg) > 0:
        actions.append(
            f"Reduce exposure: close/limit high-risk inbound ports, review public IP usage, ensure NICs are protected by NSGs."
        )
    if int(unencrypted) > 0 or int(weak_tls) > 0:
        actions.append(
            "Harden storage security: enforce TLS 1.2+, HTTPS-only, and ensure storage encryption is enabled."
        )
    if not actions:
        actions.append("No critical actions detected for this scope. Continue monitoring and re-run periodically.")

    for i, a in enumerate(actions, 1):
        y = ensure_space(c, y, 2.5 * cm)
        c.setFont("Helvetica-Bold", 10)
        c.drawString(x, y, f"{i}.")
        y = draw_wrapped_text(c, x + 0.6 * cm, y, a, max_width - 0.6 * cm, "Helvetica", 10, leading=13)
        y -= 4

    # ---------------- Page 2: Appendix ----------------
    c.showPage()
    y = height - margin

    c.setFont("Helvetica-Bold", 18)
    c.drawString(x, y, "Technical Appendix - Evidence & Methodology")
    y -= 28

    y = draw_section_title(c, x, y, "A. Data Sources & Scope")
    sources = (
        "Azure Policy: Microsoft.PolicyInsights policyStates (NonCompliant) at resource-group scope. "
        "IAM/RBAC: Microsoft.Authorization roleAssignments at subscription scope. "
        "Defender for Cloud: Microsoft.Security assessments (Unhealthy only) at RG scope. "
        "Network: NSG rules, NIC protection, public IP exposure. "
        "Encryption: storage account encryption, TLS, and HTTPS enforcement."
    )
    y = draw_wrapped_text(c, x, y, sources, max_width, "Helvetica", 10, leading=13)
    y -= 10

    y = draw_section_title(c, x, y, "B. Top Non-Compliant Policies (by records)")
    if top_policies:
        headers = ["Policy Definition ID", "Records"]
        rows = []
        for item in top_policies[:10]:
            pdid = truncate_text(str(item.get("policyDefinitionId", "")), 85)
            recs = str(item.get("noncompliant_records", ""))
            rows.append([pdid, recs])
        col_widths = [max_width - 3.2 * cm, 3.2 * cm]
        y = draw_table(c, x, y, headers, rows, col_widths)
    else:
        y = draw_wrapped_text(c, x, y, "No policy data available.", max_width)

    y -= 10
    y = draw_section_title(c, x, y, "C. IAM Evidence (samples)")
    iam_txt = f"Drift: {iam_drift}. Owners={owners}, Contributors={contributors}, Readers={readers}. Samples below."
    y = draw_wrapped_text(c, x, y, iam_txt, max_width, "Helvetica", 10, leading=13)
    y -= 6

    if owner_sample:
        c.setFont("Helvetica-Bold", 11)
        c.drawString(x, y, "Owner principals (sample)")
        y -= 16
        headers = ["Principal ID", "Type"]
        rows = []
        for p in owner_sample[:8]:
            rows.append([truncate_text(str(p.get("principalId", "")), 70), str(p.get("principalType", ""))])
        col_widths = [max_width - 4 * cm, 4 * cm]
        y = draw_table(c, x, y, headers, rows, col_widths)

    if contrib_sample:
        y -= 6
        c.setFont("Helvetica-Bold", 11)
        c.drawString(x, y, "Contributor principals (sample)")
        y -= 16
        headers = ["Principal ID", "Type"]
        rows = []
        for p in contrib_sample[:8]:
            rows.append([truncate_text(str(p.get("principalId", "")), 70), str(p.get("principalType", ""))])
        col_widths = [max_width - 4 * cm, 4 * cm]
        y = draw_table(c, x, y, headers, rows, col_widths)

    # ---------------- Page 3: Methodology ----------------
    c.showPage()
    y = height - margin

    y = draw_section_title(c, x, y, "D. Scoring Methodology (Normalized)")
    meth = [
        "Each component produces a bounded sub-score: Policy(0-40), IAM(0-35), Defender(0-35), Network(0-15), Encryption(0-10).",
        "Raw total = sum(component scores). Max possible = 135.",
        "Final RiskScore = min(100, round((RawTotal / 135) × 100)).",
        "Risk Level thresholds: Low<10, Low-Medium<25, Medium<40, Medium-High<60, High<75, Critical≥75 (or critical component + score≥50).",
    ]
    for line in meth:
        y = draw_wrapped_text(c, x + 0.4 * cm, y, f"- {line}", max_width - 0.4 * cm, "Helvetica", 10, leading=13)
        y -= 2

    y -= 8
    y = draw_section_title(c, x, y, "E. Notes & Limitations")
    notes = (
        "Defender counts may be 0 if Defender for Cloud is not enabled or not fully initialized. "
        "IAM drift is computed using threshold-based heuristics and should be tuned to organizational baselines. "
        "Network/encryption checks depend on RBAC permissions and available resources in the RG."
    )
    y = draw_wrapped_text(c, x, y, notes, max_width, "Helvetica", 10, leading=13)

    c.save()
    print(f"[OK] PDF report generated successfully: {output_pdf}")


if __name__ == "__main__":
    main()
