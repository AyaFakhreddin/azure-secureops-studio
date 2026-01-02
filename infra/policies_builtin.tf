########################################
# Built-in Policies Assignments 
# - Allowed locations (Deny)
# - Secure transfer required for Storage Accounts (Deny)
# - Deploy Diagnostics for Stream Analytics to Log Analytics (DeployIfNotExists)



# 1️⃣ Allowed locations (built-in)
resource "azurerm_subscription_policy_assignment" "assign_allowed_locations" {
  name                 = "aoss-assign-allowed-locations"
  display_name         = "AOSS - Allowed Locations"
  subscription_id      = var.subscription_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"

  parameters = jsonencode({
    listOfAllowedLocations = {
      value = ["francecentral", "westeurope"]
    }
  })
}

# 2️⃣ Secure transfer required for Storage Accounts (built-in)
resource "azurerm_subscription_policy_assignment" "assign_secure_transfer_storage" {
  name                 = "aoss-assign-secure-transfer-storage"
  display_name         = "AOSS - Secure transfer required for storage accounts"
  subscription_id      = var.subscription_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/404c3081-a854-4457-ae30-26a93ef643f9"

  # Cette built-in est de type "Deny" → pas besoin de paramètres supplémentaires.
}

# 3️⃣ Deploy Diagnostic Settings for Stream Analytics to Log Analytics (built-in)
resource "azurerm_subscription_policy_assignment" "assign_deploy_diag_stream" {
  name                 = "aoss-assign-deploy-diagnostics-stream"
  display_name         = "AOSS - Deploy diagnostics for Stream Analytics to Log Analytics"
  subscription_id      = var.subscription_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/237e0f7e-b0e8-4ec4-ad46-8c12cb66d673"

  # Obligatoire pour DeployIfNotExists
 location = "francecentral"

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    effect = {
      value = "DeployIfNotExists"
    }
    logAnalytics = {
      value = var.log_analytics_workspace_id
    }
    profileName = {
      value = "setbypolicy_logAnalytics"
    }
    metricsEnabled = {
      value = "False"
    }
    logsEnabled = {
      value = "True"
    }
  })
 }
