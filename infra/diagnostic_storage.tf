########################################
# Deploy Storage Diagnostics to Log Analytics (Custom DINE)
########################################

# You MUST provide this from your existing Log Analytics workspace.
# Example: pass it from output of your LAW module, or define it in variables.tf + tfvars.
# variable "log_analytics_workspace_id" { type = string }

resource "azurerm_policy_definition" "deploy_storage_diagnostics" {
  name         = "deploy-storage-diagnostics"
  display_name = "Deploy Storage Diagnostics to Log Analytics"
  policy_type  = "Custom"
  mode         = "Indexed"

  description = "Deploy diagnostic settings on Storage Accounts to send logs to a Log Analytics Workspace."

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

        # IMPORTANT: These roles are what Azure Policy uses for the assignment MI.
        # Monitoring Contributor = write diagnostic settings
        # Contributor = create ARM deployments (deployments/write)
        roleDefinitionIds = [
          "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c", # Contributor
          "/providers/Microsoft.Authorization/roleDefinitions/749f88d5-cbae-40b8-bcfc-e573ddc772fa"  # Monitoring Contributor
        ]

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

                  # THIS is the correct way: diagnosticSettings scoped to the storage account
                  scope = "[resourceId('Microsoft.Storage/storageAccounts', parameters('storageAccountName'))]"

                  properties = {
                    workspaceId = "[parameters('workspaceId')]"
                    logs = [
                      { category = "StorageRead",   enabled = true },
                      { category = "StorageWrite",  enabled = true },
                      { category = "StorageDelete", enabled = true }
                    ]
                  }
                }
              ]
            }
          }
        }
      }
    }
  })

  metadata = jsonencode({
    category = "Monitoring"
    version  = "1.0.0"
  })
}

########################################
# Assignment (Identity + Location is REQUIRED)
########################################
resource "azurerm_subscription_policy_assignment" "deploy_storage_diagnostics_assignment" {
  name                 = "deploy-storage-diagnostics-assignment"
  display_name         = "Deploy Storage Diagnostics Assignment"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.deploy_storage_diagnostics.id

  # REQUIRED because identity is used
  location = azurerm_resource_group.rg.location

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    logAnalyticsWorkspaceId = {
      value = var.log_analytics_workspace_id
    }
  })
}

########################################
# CRITICAL: ensure assignment MI has rights on the RG
# (this prevents PolicyAuthorizationFailed deployments/write)
########################################
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
