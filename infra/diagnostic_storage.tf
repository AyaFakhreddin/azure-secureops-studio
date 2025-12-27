#############################################
# Deploy Storage Diagnostics to Log Analytics
# (Custom DeployIfNotExists + Remediation Task)
#############################################

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

        # Roles required for DeployIfNotExists:
        # - Contributor: allows deployments/write (PolicyDeployment_* in RG)
        # - Monitoring Contributor: allows writing diag settings (optional if Contributor already granted)
        roleDefinitionIds = [
          "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c",
          "/providers/Microsoft.Authorization/roleDefinitions/749f88d5-cbae-40b8-bcfc-e573ddc772fa"
        ]
      }
    }
  })

  metadata = jsonencode({
    category = "Monitoring"
    version  = "1.0.0"
  })
}

resource "azurerm_subscription_policy_assignment" "deploy_storage_diagnostics_assignment" {
  name                 = "deploy-storage-diagnostics-assignment"
  display_name         = "Deploy Storage Diagnostics Assignment"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = azurerm_policy_definition.deploy_storage_diagnostics.id

  # REQUIRED because identity is enabled
  location = azurerm_resource_group.rg.location

  identity {
    type = "SystemAssigned"
  }

  # IMPORTANT: must be the LAW workspace id
  parameters = jsonencode({
    logAnalyticsWorkspaceId = {
      value = var.log_analytics_workspace_id
    }
  })
}

# Give the assignment identity rights on the RG (THIS fixes PolicyAuthorizationFailed)
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

# Optional but recommended: ensure role assignments exist before you run remediation in pipeline
# (Pipeline will run after deploy anyway, but this avoids timing issues)
