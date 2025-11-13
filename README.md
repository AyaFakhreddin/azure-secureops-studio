# azure-secureops-studio
# Azure SecureOps Studio

A small, demo-friendly platform to practice **DevSecOps + SOC on Azure**.  
It has three modules:
- **Policy Hub (Guardrails-as-Code):** apply & verify Azure security policies.
- **AccessLens Lite:** snapshot RBAC (who-has-what) and detect drift.
- **RiskScore 360:** simple risk scoring from Defender for Cloud + policy compliance.

## Why this repo?
- Reproducible environment using IaC (Terraform) + GitHub Actions.
- No secrets in CI: we use **GitHub OIDC** to log in to Azure.

## Repo Structure (initial)
