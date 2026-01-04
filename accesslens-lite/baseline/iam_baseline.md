# AccessLens Lite – IAM Baseline

## 1. Scope
This document defines the Identity and Access Management (IAM) baseline
for an Azure enterprise subscription.

Scope:
- Azure Subscription level
- Role-Based Access Control (RBAC)
- Human users and automation identities (CI/CD, managed identities)

## 2. Security Principles
The following security principles are applied:
- Least Privilege
- Separation of duties
- No permanent privileged access for automation identities
- Full traceability of IAM changes

## 3. Baseline IAM Rules

### 3.1 Owner (Critical Role)
Allowed:
- Very limited number of human administrators
- Maximum of 1 to 3 Owners
- Internal users only

Not Allowed:
- Service Principals assigned as Owner
- Managed Identities assigned as Owner
- Guest users assigned as Owner

Rationale:
The Owner role provides full control over the subscription and represents
a critical security risk if misused or compromised.

### 3.2 User Access Administrator (Privileged Role)
Allowed:
- Dedicated automation identity (CI/CD) for controlled remediation tasks

Not Allowed:
- Multiple human users
- Guest users

### 3.3 Contributor (High Privilege Role)
Allowed:
- CI/CD automation identities
- Managed identities used for remediation or automation
- Limited number of technical users

Not Allowed:
- Guest users
- Broad or unjustified assignments at subscription scope

### 3.4 Reader (Low Privilege Role)
Allowed:
- Audit and monitoring users or groups

## 4. IAM Drift Definition
An IAM drift is defined as:
- Any new Owner assignment
- Any Owner assignment to a non-human identity
- Any increase in privileged role assignments beyond the baseline
- Any privileged role assigned without proper justification

## 5. Expected Detection Signals
The following Azure operations must be monitored:
- Microsoft.Authorization/roleAssignments/write
- Microsoft.Authorization/roleAssignments/delete
