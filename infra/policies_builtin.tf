####################################
# 1. Récupérer les définitions BUILT-IN
####################################

# Allowed locations
data "azurerm_policy_definition" "allowed_locations" {
  name = "e56962a6-4747-49cd-b67b-bf8b01975c4c"
}

# Require a tag and its value on resources
data "azurerm_policy_definition" "require_tag" {
  name = "1e30110a-5ceb-460c-a204-c1c3969c6d62"
}

# Secure transfer for storage accounts
data "azurerm_policy_definition" "secure_transfer" {
  name = "404c3081-a854-4457-ae30-26a93ef643f9"
}

# Deploy diagnostic settings for Storage accounts to Log Analytics workspace
data "azurerm_policy_definition" "deploy_diag_stream" {
  name = "237e0f7e-b0e8-4ec4-ad46-8c12cb66d673"
}

####################################
# 2. Assignations au niveau Subscription
####################################

# 2.1 Allowed locations
resource "azurerm_subscription_policy_assignment" "assign_allowed_locations" {
  name                 = "aoss-assign-allowed-locations"
  display_name         = "AOSS - Allowed locations"
  subscription_id      = var.subscription_id
  policy_definition_id = data.azurerm_policy_definition.allowed_locations.id

  parameters = jsonencode({
    listOfAllowedLocations = {
      value = ["francecentral", "westeurope"]
    }
  })
}

# 2.2 Require tag Owner
#resource "azurerm_subscription_policy_assignment" "assign_require_tag_owner" {
#  name                 = "aoss-assign-require-tag-owner"
#  display_name         = "AOSS - Require tag Owner on resources"
#  subscription_id      = var.subscription_id
#  policy_definition_id = data.azurerm_policy_definition.require_tag.id#
#
#  parameters = jsonencode({
#    tagName = {
#      value = "Owner"
#    }
#    tagValue = {
#      value = "NotSet"
#    }
#  })
#}

# 2.3 Secure transfer for Storage Accounts
resource "azurerm_subscription_policy_assignment" "assign_secure_transfer_storage" {
  name                 = "aoss-assign-secure-transfer-storage"
  display_name         = "AOSS - Secure transfer required for storage accounts"
  subscription_id      = var.subscription_id
  policy_definition_id = data.azurerm_policy_definition.secure_transfer.id
}

# 2.4 Deploy Diagnostic Settings for Stream Analytics to Log Analytics
resource "azurerm_subscription_policy_assignment" "assign_deploy_diag_stream" {
  name                 = "aoss-assign-deploy-diagnostics-stream"
  display_name         = "AOSS - Deploy diagnostics for Stream Analytics to Log Analytics"
  subscription_id      = var.subscription_id
  policy_definition_id = data.azurerm_policy_definition.deploy_diag_stream.id

  # obligatoire pour DeployIfNotExists
  location = "francecentral" # ou la même région que ton LAW (France Central)

  identity {
    type = "SystemAssigned"
  }

  parameters = jsonencode({
    effect = {
      value = "DeployIfNotExists"
    }
    profileName = {
      value = "setbypolicy_logAnalytics"
    }
    logAnalytics = {
      value = var.log_analytics_workspace_id
    }
    metricsEnabled = {
      value = "False"
    }
    logsEnabled = {
      value = "True"
    }
  })
}