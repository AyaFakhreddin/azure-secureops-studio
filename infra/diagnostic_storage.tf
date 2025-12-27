########################################
# diagnostic_storage.tf
# Deploy Storage Diagnostics to Log Analytics (Custom DINE)
########################################

# Policy definition
resource "azurerm_policy_definition" "deploy_storage_diagnostics" {
  name         = "deploy-storage-diagnostics"
  display_name = "Deploy Storage Diagnostics to Log Analytics"
  policy_type  = "Custom"
  mode         = "Indexed"
  description  = "Deploy diagnostic settings to Storage Accounts and send logs to Log Analytics."

  parameters = jsonencode({
    logAnalyticsWorkspaceId = {
      type = "String"
      metadata = {
        displayName = "Log Analytics Workspace Resource ID"
      }
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

        # If a diagnostic setting exists with logs enabled, consider compliant
        existenceCondition = {
          allOf = [
            {
              field  = "Microsoft.Insights/diagnosticSettings/logs.enabled"
              equals = "true"
            },
            {
              field  = "Microsoft.Insights/diagnosticSettings/workspaceId"
              equals = "[parameters('logAnalyticsWorkspaceId')]"
            }
          ]
        }

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
                  type       = "Microsoft.Insights/diagnosticSettings"
                  apiVersion = "2021-05-01-preview"
                  name       = "set-by-policy"

                  # IMPORTANT: scope is the Storage Account
                  scope = "[resourceId('Microsoft.Storage/storageAccounts', parameters('storageAccountName'))]"

                  properties = {
                    workspaceId = "[parameters('workspaceId')]"
                    logs = [
                      { category = "StorageRead",   enabled = true },
                      { category = "StorageWrite",  enabled = true },
                      { category = "StorageDelete", enabled = true }
                    ]
                    metrics = [
                      { category = "Transaction", enabled = true }
                    ]
                  }
                }
              ]
            }
          }
        }

        # Permissions needed by the policy assignment identity
        roleDefinitionIds = [
          # Contributor (deployments/write)
          "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c",
          # Monitoring Contributor (write diagnostic settings)
          "/providers/Microsoft.Authorization/roleDefinitions/749f88d5-cbae-40b8-bcfc-e573ddc772fa"
        ]
      }
    }
  })

  metadata = jsonencode({
    category = "Monitoring"
    version  = "1.0.1"
  })
}

# Policy assignment (WITH identity)
resource "azurerm_subscription_policy_assignment" "deploy_storage_diagnostics_assignment" {
  name                 = "deploy-storage-diagnostics-assignment"
  display_name         = "Deploy Storage Diagnostics Assignment"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.deploy_storage_diagnostics.id

  # REQUIRED because identity exists
  location = azurerm_resource_group.rg.location

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    logAnalyticsWorkspaceId = {
      value = azurerm_log_analytics_workspace.law.id
    }
  })
}

# Give the assignment identity permissions on the RG
resource "azurerm_role_assignment" "deploy_storage_diag_rg_contributor" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_subscription_policy_assignment.deploy_storage_diagnostics_assignment.identity[0].principal_id
}

resource "azurerm_role_assignment" "deploy_storage_diag_rg_monitoring_contrib" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Monitoring Contributor"
  principal_id         = azurerm_subscription_policy_assignment.deploy_storage_diagnostics_assignment.identity[0].principal_id
}
