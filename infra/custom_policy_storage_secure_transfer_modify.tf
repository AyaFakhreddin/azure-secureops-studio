########################################
# Custom Policy - Modify Secure Transfer on existing Storage Accounts
########################################

resource "azurerm_policy_definition" "modify_secure_transfer_storage" {
  name         = "modify-secure-transfer-storage"
  display_name = "AOSS - Remediate existing Storage Accounts (enable secure transfer)"
  policy_type  = "Custom"
  mode         = "Indexed"
  description  = "Automatically enables secure transfer (HTTPS only) on existing Storage Accounts."

  policy_rule = jsonencode({
    "if" = {
      "allOf" = [
        {
          "field"  = "type",
          "equals" = "Microsoft.Storage/storageAccounts"
        },
        {
          "anyOf" = [
            {
              "field"  = "Microsoft.Storage/storageAccounts/supportsHttpsTrafficOnly",
              "equals" = "false"
            },
            {
              "field"  = "Microsoft.Storage/storageAccounts/supportsHttpsTrafficOnly",
              "exists" = "false"
            }
          ]
        }
      ]
    },
    "then" = {
      "effect" = "Modify",
      "details" = {
        # Contributor roleDefinitionId (needed for write)
        "roleDefinitionIds" = [
          "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
        ],
        "operations" = [
          {
            "operation" : "addOrReplace",
            "field" : "Microsoft.Storage/storageAccounts/supportsHttpsTrafficOnly",
            "value" : true
          }
        ]
      }
    }
  })

  metadata = jsonencode({
    category = "Security"
    version  = "1.0.0"
  })
}

resource "azurerm_subscription_policy_assignment" "assign_modify_secure_transfer" {
  name                 = "aoss-assign-remediate-secure-transfer-storage"
  subscription_id      = var.subscription_id
  policy_definition_id = azurerm_policy_definition.modify_secure_transfer_storage.id

  location = "francecentral"

  identity {
    type = "SystemAssigned"
  }
}