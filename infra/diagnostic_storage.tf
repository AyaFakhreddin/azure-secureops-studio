#############################################
# diagnostic_storage.tf  (FINAL - WORKING)
#############################################

# ------------------------------------------------------------
# VARIABLES (make sure these exist in your project)
# ------------------------------------------------------------
# You MUST provide:
# - var.subscription_id (or use data.azurerm_subscription.current.id)
# - var.log_analytics_workspace_id (LAW resource id)
# - var.resource_group_name + var.resource_group_location (your RG)


# ------------------------------------------------------------
# POLICY DEFINITION (DeployIfNotExists) - FIXED categories
# ------------------------------------------------------------
resource "azurerm_policy_definition" "deploy_storage_diagnostics" {
  name         = "deploy-storage-diagnostics"
  display_name = "Deploy Storage Diagnostics to Log Analytics"
  policy_type  = "Custom"
  mode         = "Indexed"
  description  = "Deploy diagnostic settings on Storage Accounts to send logs to Log Analytics."

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

        # Needed so the policy can create the deployment + write diag settings
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
                  type       = "Microsoft.Storage/storageAccounts/providers/diagnosticSettings"
                  apiVersion = "2021-05-01-preview"
                  name       = "[concat(parameters('storageAccountName'), '/Microsoft.Insights/set-by-policy')]"
                  properties = {
                    workspaceId = "[parameters('workspaceId')]"

                    # FIX: avoid invalid categories like StorageRead/Write/Delete
                    logs = [
                      {
                        categoryGroup = "allLogs"
                        enabled       = true
                      }
                    ]

                    metrics = [
                      {
                        category = "Transaction"
                        enabled  = true
                      }
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

# ------------------------------------------------------------
# POLICY ASSIGNMENT (with identity + location)
# IMPORTANT: location is REQUIRED when identity is used
# ------------------------------------------------------------
resource "azurerm_subscription_policy_assignment" "deploy_storage_diagnostics_assignment" {
  name                 = "deploy-storage-diagnostics-assignment"
  display_name         = "Deploy Storage Diagnostics Assignment"
  subscription_id      = var.subscription_id
  policy_definition_id = azurerm_policy_definition.deploy_storage_diagnostics.id

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

# ------------------------------------------------------------
# ROLE ASSIGNMENTS FOR THE POLICY ASSIGNMENT IDENTITY ON YOUR RG
# This is mandatory, otherwise remediation deployments fail
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# AUTO REMEDIATION (Terraform triggers remediation for existing noncompliant)
# ------------------------------------------------------------
resource "azurerm_policy_remediation" "remediate_storage_diag" {
  name                 = "remediate-storage-diag"
  scope                = "/subscriptions/${var.subscription_id}"
  policy_assignment_id = azurerm_subscription_policy_assignment.deploy_storage_diagnostics_assignment.id

  resource_discovery_mode = "ExistingNonCompliant"

  # IMPORTANT: must match location(s) where resources are
  location_filters = [var.resource_group_location]

  depends_on = [
    azurerm_role_assignment.deploy_storage_diag_rg_contributor,
    azurerm_role_assignment.deploy_storage_diag_rg_monitoring_contrib
  ]
}
