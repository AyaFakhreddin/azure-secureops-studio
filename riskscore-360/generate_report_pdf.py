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
    """Check if there's enough space, create new page if not"""
    if y < needed:
        c.showPage()
        return A4[1] - 3.0 * cm
    return y


def wrap_text(c: canvas.Canvas, text: str, max_width: float, font_name: str, font_size: int) -> List[str]:
    """Wrap text to fit within max_width"""
    words = (text or "").split()
    if not words:
        return [""]

    lines = []
    current_line = ""
    
    for word in words:
        test_line = (current_line + " " + word).strip()
        if c.stringWidth(test_line, font_name, font_size) <= max_width:
            current_line = test_line
        else:
            if current_line:
                lines.append(current_line)
            current_line = word
    
    if current_line:
        lines.append(current_line)
    
    return lines if lines else [""]


def draw_wrapped_text(c: canvas.Canvas, x: float, y: float, text: str, max_width: float, 
                       font_name: str = "Helvetica", font_size: int = 10) -> float:
    """Draw wrapped text and return new y position"""
    c.setFont(font_name, font_size)
    lines = wrap_text(c, text, max_width, font_name, font_size)
    
    for line in lines:
        c.drawString(x, y, line)
        y -= font_size + 4
    
    return y


def draw_section_title(c: canvas.Canvas, x: float, y: float, title: str) -> float:
    """Draw a section title with spacing"""
    c.setFillColor(HexColor("#1a1a1a"))
    c.setFont("Helvetica-Bold", 14)
    c.drawString(x, y, title)
    c.setFillColor(HexColor("#000000"))
    return y - 22


def draw_key_value(c: canvas.Canvas, x: float, y: float, key: str, value: str, 
                   max_width: float, key_width: float = 4.5 * cm) -> float:
    """Draw key-value pair with proper wrapping"""
    c.setFont("Helvetica-Bold", 10)
    c.drawString(x, y, f"{key}:")
    
    value_x = x + key_width
    value_width = max_width - key_width - 0.5 * cm
    
    y = draw_wrapped_text(c, value_x, y, str(value), value_width, "Helvetica", 10)
    return y - 6


def truncate_text(text: str, max_len: int = 80) -> str:
    """Truncate text with ellipsis in middle"""
    text = str(text or "")
    if len(text) <= max_len:
        return text
    
    keep = max_len - 3
    left = keep // 2
    right = keep - left
    return f"{text[:left]}...{text[-right:]}"


def draw_table(c: canvas.Canvas, x: float, y: float, headers: List[str], 
               rows: List[List[str]], col_widths: List[float]) -> float:
    """Draw a table with headers and rows"""
    row_height = 18
    padding = 4
    
    # Draw header background
    header_bg = HexColor("#f0f0f0")
    c.setFillColor(header_bg)
    c.rect(x, y - row_height + 4, sum(col_widths), row_height, fill=1, stroke=0)
    
    # Draw headers
    c.setFillColor(HexColor("#000000"))
    c.setFont("Helvetica-Bold", 10)
    curr_x = x + padding
    for i, header in enumerate(headers):
        c.drawString(curr_x, y - 12, header)
        curr_x += col_widths[i]
    
    y -= row_height
    
    # Draw rows
    c.setFont("Helvetica", 9)
    for row in rows:
        y = ensure_space(c, y, 3 * cm)
        
        curr_x = x + padding
        max_lines = 1
        wrapped_cells = []
        
        # Wrap each cell
        for i, cell in enumerate(row):
            cell_width = col_widths[i] - (2 * padding)
            lines = wrap_text(c, str(cell), cell_width, "Helvetica", 9)
            wrapped_cells.append(lines)
            max_lines = max(max_lines, len(lines))
        
        # Draw each line
        for line_idx in range(max_lines):
            curr_x = x + padding
            for col_idx, lines in enumerate(wrapped_cells):
                if line_idx < len(lines):
                    c.drawString(curr_x, y - (line_idx * 12) - 10, lines[line_idx])
                curr_x += col_widths[col_idx]
        
        y -= (max_lines * 12) + padding
    
    return y - 10


# ----------------------------
# Main report generation
# ----------------------------

def main() -> None:
    repo_root = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
    input_json = os.path.join(repo_root, "reports", "riskscore_real.json")
    output_pdf = os.path.join(repo_root, "reports", "secureops_riskscore2_report.pdf")

    if not os.path.exists(input_json):
        raise FileNotFoundError(
            f"Missing {input_json}\n"
            f"Generate it with:\n"
            f"  python riskscore-360/compute_score.py > reports/riskscore_real.json"
        )

    data: Dict[str, Any] = safe_load_json(input_json)

    # Extract data
    sub_id = data.get("subscription_id", "unknown")
    rg = data.get("resource_group", "unknown")
    score = data.get("risk_score", "N/A")
    level = data.get("risk_level", "N/A")

    policy_risk = data.get("policy_risk", 0)
    iam_risk = data.get("iam_risk", 0)
    defender_risk = data.get("defender_risk", 0)

    raw = data.get("raw_inputs", {}) or {}

    policy_raw = raw.get("policy", {}) or {}
    unique_nc = policy_raw.get("unique_noncompliant_policies", 0)
    top_policies = policy_raw.get("top_noncompliant_policies", []) or []

    iam_raw = raw.get("iam", {}) or {}
    iam_drift = iam_raw.get("drift", "none")
    iam_counts = iam_raw.get("counts", {}) or {}
    owners = iam_counts.get("owners", "N/A")
    contributors = iam_counts.get("contributors", "N/A")
    owner_sample = iam_raw.get("owner_principals_sample", []) or []
    contrib_sample = iam_raw.get("contributor_principals_sample", []) or []

    defender_raw = raw.get("defender", {}) or {}
    high = defender_raw.get("high", 0)
    medium = defender_raw.get("medium", 0)

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    # Create PDF
    c = canvas.Canvas(output_pdf, pagesize=A4)
    width, height = A4
    margin = 2.5 * cm
    x = margin
    y = height - margin
    max_width = width - (2 * margin)

    # -------------------------
    # Page 1: Executive Report
    # -------------------------
    
    # Title
    c.setFont("Helvetica-Bold", 20)
    c.drawString(x, y, "SecureOps RiskScore 360")
    y -= 24
    c.setFont("Helvetica", 16)
    c.drawString(x, y, "Security Assessment Report")
    y -= 35

    # Metadata
    y = draw_key_value(c, x, y, "Generated", now, max_width)
    y = draw_key_value(c, x, y, "Subscription", truncate_text(sub_id, 60), max_width)
    y = draw_key_value(c, x, y, "Resource Group", str(rg), max_width)
    y -= 20

    # Executive Summary
    y = draw_section_title(c, x, y, "1. Executive Summary")
    
    # Risk Score Box
    box_width = 6 * cm
    box_height = 2.5 * cm
    
    # Determine color based on risk level
    level_str = str(level).upper()
    if "HIGH" in level_str or "CRITICAL" in level_str:
        box_color = HexColor("#d32f2f")
    elif "MEDIUM" in level_str:
        box_color = HexColor("#f57c00")
    else:
        box_color = HexColor("#388e3c")
    
    c.setFillColor(box_color)
    c.rect(x, y - box_height, box_width, box_height, fill=1, stroke=0)
    
    c.setFillColor(HexColor("#ffffff"))
    c.setFont("Helvetica-Bold", 40)
    c.drawString(x + 1 * cm, y - 1.6 * cm, str(score))
    c.setFont("Helvetica-Bold", 12)
    c.drawString(x + 0.5 * cm, y - 2.2 * cm, f"Risk Level: {level}")
    
    c.setFillColor(HexColor("#000000"))
    y -= box_height + 20

    summary_text = (
        "This report consolidates governance compliance (Azure Policy), identity governance "
        "(RBAC/IAM drift), and security posture signals (Defender for Cloud) into a normalized "
        "risk score to support prioritization."
    )
    y = draw_wrapped_text(c, x, y, summary_text, max_width, "Helvetica", 10)
    y -= 20

    # Score Breakdown
    y = ensure_space(c, y, 8 * cm)
    y = draw_section_title(c, x, y, "2. Score Breakdown")
    
    headers = ["Component", "Value", "Details"]
    rows = [
        ["Policy Risk", str(policy_risk), f"{unique_nc} unique non-compliant policies"],
        ["IAM Risk", str(iam_risk), f"Drift: {iam_drift} (Owners: {owners}, Contributors: {contributors})"],
        ["Defender Risk", str(defender_risk), f"High: {high}, Medium: {medium}"],
        ["Total RiskScore", str(score), f"Level: {level}"]
    ]
    col_widths = [3.5 * cm, 2.5 * cm, max_width - 6 * cm]
    
    y = draw_table(c, x, y, headers, rows, col_widths)
    y -= 15

    # Recommended Actions
    y = ensure_space(c, y, 6 * cm)
    y = draw_section_title(c, x, y, "3. Recommended Actions")
    
    actions = []
    if int(unique_nc) > 0:
        actions.append(
            f"Remediate {unique_nc} non-compliant Azure policies in resource group '{rg}'. "
            "Prioritize the most frequent policies listed in the appendix."
        )
    if str(iam_drift).lower() in ("owner", "contributor"):
        actions.append(
            f"Review RBAC assignments to reduce privilege sprawl. Current: {owners} Owners, "
            f"{contributors} Contributors. Ensure each Owner role is justified."
        )
    if int(high) + int(medium) > 0:
        actions.append(
            f"Address {int(high) + int(medium)} Defender for Cloud unhealthy assessments "
            f"(High: {high}, Medium: {medium})."
        )
    if not actions:
        actions.append("No critical actions detected. Continue monitoring.")
    
    for i, action in enumerate(actions, 1):
        y = ensure_space(c, y, 3 * cm)
        c.setFont("Helvetica-Bold", 10)
        c.drawString(x, y, f"{i}.")
        y = draw_wrapped_text(c, x + 0.7 * cm, y, action, max_width - 0.7 * cm, "Helvetica", 10)
        y -= 8

    # -------------------------
    # Page 2: Technical Appendix
    # -------------------------
    c.showPage()
    y = height - margin

    c.setFont("Helvetica-Bold", 18)
    c.drawString(x, y, "Technical Appendix")
    y -= 30

    # Data Sources
    y = draw_section_title(c, x, y, "A. Data Sources")
    sources_text = (
        "Azure Policy: Microsoft.PolicyInsights policyStates (NonCompliant) at RG scope. "
        "IAM: Microsoft.Authorization roleAssignments at subscription scope. "
        "Defender: Microsoft.Security assessments (Unhealthy only) at RG scope."
    )
    y = draw_wrapped_text(c, x, y, sources_text, max_width, "Helvetica", 10)
    y -= 20

    # Top Non-Compliant Policies
    y = ensure_space(c, y, 6 * cm)
    y = draw_section_title(c, x, y, "B. Top Non-Compliant Policies")
    
    if top_policies:
        headers = ["Policy Definition ID", "Records"]
        rows = []
        for item in top_policies[:10]:
            pdid = truncate_text(str(item.get("policyDefinitionId", "")), 70)
            recs = str(item.get("noncompliant_records", ""))
            rows.append([pdid, recs])
        
        col_widths = [max_width - 3 * cm, 3 * cm]
        y = draw_table(c, x, y, headers, rows, col_widths)
    else:
        y = draw_wrapped_text(c, x, y, "No policy data available.", max_width, "Helvetica", 10)
    
    y -= 20

    # IAM Evidence
    y = ensure_space(c, y, 6 * cm)
    y = draw_section_title(c, x, y, "C. IAM Evidence")
    
    iam_text = (
        f"Drift classification: {iam_drift}. Owners: {owners}, Contributors: {contributors}. "
        "Sample principals with privileged roles:"
    )
    y = draw_wrapped_text(c, x, y, iam_text, max_width, "Helvetica", 10)
    y -= 10

    # Owner principals
    if owner_sample:
        y = ensure_space(c, y, 5 * cm)
        c.setFont("Helvetica-Bold", 11)
        c.drawString(x, y, "Owner Principals (sample)")
        y -= 18
        
        headers = ["Principal ID", "Type"]
        rows = []
        for p in owner_sample[:8]:
            pid = truncate_text(str(p.get("principalId", "")), 65)
            ptype = str(p.get("principalType", ""))
            rows.append([pid, ptype])
        
        col_widths = [max_width - 3.5 * cm, 3.5 * cm]
        y = draw_table(c, x, y, headers, rows, col_widths)
        y -= 15

    # Contributor principals
    if contrib_sample:
        y = ensure_space(c, y, 5 * cm)
        c.setFont("Helvetica-Bold", 11)
        c.drawString(x, y, "Contributor Principals (sample)")
        y -= 18
        
        headers = ["Principal ID", "Type"]
        rows = []
        for p in contrib_sample[:8]:
            pid = truncate_text(str(p.get("principalId", "")), 65)
            ptype = str(p.get("principalType", ""))
            rows.append([pid, ptype])
        
        col_widths = [max_width - 3.5 * cm, 3.5 * cm]
        y = draw_table(c, x, y, headers, rows, col_widths)

    # Methodology
    c.showPage()
    y = height - margin
    
    y = draw_section_title(c, x, y, "D. Scoring Methodology")
    
    methodology = [
        "Policy Risk = min(60, unique_noncompliant_policies × 5)",
        "IAM Risk = 70 (Owner drift) | 40 (Contributor drift) | 0 (none)",
        "Defender Risk = (High × 30) + (Medium × 15)",
        "Final RiskScore = min(100, Policy Risk + IAM Risk + Defender Risk)"
    ]
    
    for line in methodology:
        c.setFont("Helvetica", 10)
        c.drawString(x + 0.5 * cm, y, f"• {line}")
        y -= 16
    
    y -= 10
    
    # Limitations
    y = draw_section_title(c, x, y, "E. Notes & Limitations")
    limitations_text = (
        "Defender assessments may be 0 if Defender for Cloud is not enabled or fully initialized. "
        "IAM drift uses threshold-based classification and can be refined with organization-specific "
        "baselines and role justification processes."
    )
    y = draw_wrapped_text(c, x, y, limitations_text, max_width, "Helvetica", 10)

    c.save()
    print(f" PDF report generated successfully: {output_pdf}")


if __name__ == "__main__":
    main()