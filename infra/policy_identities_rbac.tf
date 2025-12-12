########################################
# RBAC for Azure Policy Managed Identities
# - Stream Analytics Deploy Diagnostics (DeployIfNotExists)
# - Storage Secure Transfer remediation (Modify)
########################################

# RG existant (vu dans ton backend.tf)
data "azurerm_resource_group" "aoss_rg" {
  name = "aoss-dev-rg-secops"
}

########################################
# 1 Stream Analytics diagnostics (DeployIfNotExists)
# Policy assignment: assign_deploy_diag_stream
# Needs permission to create PolicyDeployment + diagnostic settings
########################################
resource "azurerm_role_assignment" "policy_stream_diag_monitoring" {
  scope                = data.azurerm_resource_group.aoss_rg.id
  role_definition_name = "Monitoring Contributor"
  principal_id         = azurerm_subscription_policy_assignment.assign_deploy_diag_stream.identity[0].principal_id
}

# (Option recommandé si ça échoue encore)
resource "azurerm_role_assignment" "policy_stream_diag_contributor" {
  scope                = data.azurerm_resource_group.aoss_rg.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_subscription_policy_assignment.assign_deploy_diag_stream.identity[0].principal_id
}

###################################
# 2 Storage secure transfer (Modify)
# Policy assignment: assign_modify_secure_transfer
# Needs permission to update storage accounts
###################################
resource "azurerm_role_assignment" "policy_storage_rg_contributor" {
  scope                = data.azurerm_resource_group.aoss_rg.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_subscription_policy_assignment.assign_modify_secure_transfer.identity[0].principal_id
}
