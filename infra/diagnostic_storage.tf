#############################################
# Deploy Storage Diagnostics to Log Analytics
# (Custom DINE - robust categoryGroup)
#############################################

resource "azurerm_policy_definition" "deploy_storage_diagnostics" {
  name         = "deploy-storage-diagnostics"
  display_name = "Deploy Storage Diagnostics to Log Analytics"
  policy_type  = "Custom"
  mode         = "Indexed"

  metadata = jsonencode({
    category = "Monitoring"
    version  = "1.0.0"
  })

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

                    # Robust choice: categoryGroup instead of StorageRead/Write/Delete
                    logs = [
                      {
                        categoryGroup = "allLogs"
                        enabled       = true
                      }
                    ]

                    metrics = [
                      {
                        category = "AllMetrics"
                        enabled  = true
                      }
                    ]
                  }
                }
              ]
            }
          }
        }

        # These are required by DINE:
        # - Monitoring Contributor: write diagnostic settings
        # - Contributor: create ARM deployment (deployments/write) in RG
        roleDefinitionIds = [
          "/providers/Microsoft.Authorization/roleDefinitions/749f88d5-cbae-40b8-bcfc-e573ddc772fa", # Monitoring Contributor
          "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"  # Contributor
        ]
      }
    }
  })
}

#############################################
# Assignment (must have identity + location)
#############################################

resource "azurerm_subscription_policy_assignment" "deploy_storage_diagnostics_assignment" {
  name                 = "deploy-storage-diagnostics-assignment"
  display_name         = "Deploy Storage Diagnostics Assignment"
  subscription_id      = var.subscription_id
  policy_definition_id = azurerm_policy_definition.deploy_storage_diagnostics.id

  # REQUIRED when identity {} is used
  location = var.resource_group_location

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    logAnalyticsWorkspaceId = {
      value = var.log_analytics_workspace_id
    }
  })
}

#############################################
# Role assignments for the Policy MI
# Scope = your RG where storages exist
#############################################

resource "azurerm_role_assignment" "deploy_storage_diag_rg_contributor" {
  scope                = var.resource_group_id
  role_definition_name = "Contributor"
  principal_id         = azurerm_subscription_policy_assignment.deploy_storage_diagnostics_assignment.identity[0].principal_id
}

resource "azurerm_role_assignment" "deploy_storage_diag_rg_monitoring_contrib" {
  scope                = var.resource_group_id
  role_definition_name = "Monitoring Contributor"
  principal_id         = azurerm_subscription_policy_assignment.deploy_storage_diagnostics_assignment.identity[0].principal_id
}
