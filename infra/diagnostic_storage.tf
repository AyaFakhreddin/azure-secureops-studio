# Hard reference to existing RG
data "azurerm_resource_group" "target" {
  name = "aoss-dev-rg-secops"
}

resource "azurerm_policy_definition" "deploy_storage_diagnostics" {
  name         = "deploy-storage-diagnostics"
  display_name = "Deploy Storage Diagnostics to Log Analytics"
  policy_type  = "Custom"
  mode         = "Indexed"

  parameters = jsonencode({
    logAnalyticsWorkspaceId = {
      type = "String"
    }
  })

  policy_rule = jsonencode({
    if = {
      field  = "type"
      equals = "Microsoft.Storage/storageAccounts"
    }
    then = {
      effect = "deployIfNotExists"
      details = {
        type = "Microsoft.Insights/diagnosticSettings"

        deployment = {
          properties = {
            mode = "incremental"
            parameters = {
              storageAccountName = { value = "[field('name')]" }
              workspaceId        = { value = "[parameters('logAnalyticsWorkspaceId')]" }
            }
            template = {
              "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
              contentVersion = "1.0.0.0"
              parameters = {
                storageAccountName = { type = "string" }
                workspaceId        = { type = "string" }
              }
              resources = [
                {
                  type       = "Microsoft.Storage/storageAccounts/providers/diagnosticSettings"
                  apiVersion = "2021-05-01-preview"
                  name       = "[concat(parameters('storageAccountName'), '/Microsoft.Insights/set-by-policy')]"
                  properties = {
                    workspaceId = "[parameters('workspaceId')]"
                    logs = [
                      { categoryGroup = "audit",   enabled = true },
                      { categoryGroup = "allLogs", enabled = true }
                    ]
                  }
                }
              ]
            }
          }
        }

        roleDefinitionIds = [
          "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c",
          "/providers/Microsoft.Authorization/roleDefinitions/749f88d5-cbae-40b8-bcfc-e573ddc772fa"
        ]
      }
    }
  })
}

resource "azurerm_subscription_policy_assignment" "deploy_storage_diagnostics_assignment" {
  name                 = "deploy-storage-diagnostics-assignment"
  subscription_id      = var.subscription_id
  policy_definition_id = azurerm_policy_definition.deploy_storage_diagnostics.id
  location             = "francecentral"

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    logAnalyticsWorkspaceId = {
      value = var.log_analytics_workspace_id
    }
  })
}

resource "azurerm_role_assignment" "policy_rg_contributor" {
  scope                = data.azurerm_resource_group.target.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_subscription_policy_assignment.deploy_storage_diagnostics_assignment.identity[0].principal_id
}
