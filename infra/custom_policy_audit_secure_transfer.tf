########################################
# Custom Policy - Audit Storage Accounts without Secure Transfer
########################################

# ⚠️ Si tu as déjà :
# data "azurerm_subscription" "current" {}
# dans un autre fichier (ex: enforce_owner_tag.tf),
# NE PAS le redéclarer ici.


resource "azurerm_policy_definition" "audit_secure_transfer" {
  name         = "audit-secure-transfer"
  display_name = "Audit Storage Accounts Without Secure Transfer"
  policy_type  = "Custom"
  mode         = "Indexed"
  description  = "Audit storage accounts where secure transfer is not enabled."

  policy_rule = jsonencode({
    "if" = {
      "allOf" = [
        {
          "field"  = "type"
          "equals" = "Microsoft.Storage/storageAccounts"
        },
        {
          "field"  = "Microsoft.Storage/storageAccounts/supportsHttpsTrafficOnly"
          "equals" = "false"
        }
      ]
    }
    "then" = {
      "effect" = "audit"
    }
  })

  metadata = jsonencode({
    category = "Security"
    version  = "1.0.0"
  })
}

resource "azurerm_subscription_policy_assignment" "audit_secure_transfer_assignment" {
  name                 = "aoss-audit-secure-transfer"
  display_name         = "AOSS - Audit Storage Accounts without Secure Transfer"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.audit_secure_transfer.id
}
