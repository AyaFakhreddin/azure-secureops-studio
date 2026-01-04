# RiskScore 360 — Risk Quantification Module

## 1. Objective

RiskScore 360 is a risk prioritization module designed to aggregate multiple security signals into a single normalized risk score.  
Its goal is to help security teams quickly identify which resource group requires immediate attention.

This module builds on:
- Azure Policy compliance (governance posture)
- IAM drift detection (AccessLens Lite)
- Microsoft Defender for Cloud recommendations

---

## 2. Inputs and Data Sources

### 2.1 Policy Compliance
Non-compliant Azure Policies increase governance risk.  
Each non-compliance indicates a deviation from security best practices.

### 2.2 IAM Drift (AccessLens Lite)
Unauthorized role assignments (Contributor or Owner) represent identity and privilege escalation risks.

### 2.3 Security Exposure (Defender for Cloud)
Defender recommendations are classified by severity (High, Medium).  
Higher severity findings contribute more to the overall risk.

---

## 3. Risk Scoring Model

### 3.1 Formula

