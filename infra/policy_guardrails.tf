resource "azurerm_policy_definition" "deny_public_ip" {
  name         = "deny-public-ip"
  display_name = "Deny Public IP addresses"
  policy_type  = "Custom"
  mode         = "Indexed"
  description  = "Deny creation of Public IP resources."

  policy_rule = jsonencode({
    if = {
      field  = "type"
      equals = "Microsoft.Network/publicIPAddresses"
    }
    then = {
      effect = "deny"
    }
  })

  metadata = jsonencode({
    category = "Network"
    version  = "1.0.0"
  })
}

resource "azurerm_subscription_policy_assignment" "deny_public_ip_assignment" {
  name                 = "deny-public-ip-assignment"
  display_name         = "Deny Public IP Assignment"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.deny_public_ip.id
}

# =========================================================
# AUDIT Storage Diagnostics (non bloquant)
# =========================================================
resource "azurerm_policy_definition" "audit_storage_diag" {
  name         = "audit-storage-diagnostic-logs"
  display_name = "Audit Storage Accounts Diagnostic Settings"
  policy_type  = "Custom"
  mode         = "Indexed"
  description  = "Audit storage accounts without diagnostic settings."

  policy_rule = jsonencode({
    if = {
      field  = "type"
      equals = "Microsoft.Storage/storageAccounts"
    }
    then = {
      effect = "audit"
    }
  })

  metadata = jsonencode({
    category = "Monitoring"
    version  = "1.0.0"
  })
}

resource "azurerm_subscription_policy_assignment" "audit_storage_diag_assignment" {
  name                 = "audit-storage-diag-assignment"
  display_name         = "Audit Storage Diagnostics Assignment"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.audit_storage_diag.id
}

# ====================================
# NEW: Audit Missing Owner Tag (for remediation)
# ====================================
resource "azurerm_policy_definition" "audit_owner_tag" {
  name         = "audit-owner-tag"
  display_name = "Audit Missing Owner Tag"
  policy_type  = "Custom"
  mode         = "Indexed"
  description  = "Audit resources that do not have the 'Owner' tag."

  policy_rule = jsonencode({
    if = {
      field  = "tags['Owner']"
      exists = "false"
    }
    then = {
      effect = "audit"
    }
  })

  metadata = jsonencode({
    category = "Tags"
    version  = "1.0.0"
  })
}

resource "azurerm_subscription_policy_assignment" "audit_owner_tag_assignment" {
  name                 = "audit-owner-tag-assignment"
  display_name         = "Audit Owner Tag Assignment"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.audit_owner_tag.id
}