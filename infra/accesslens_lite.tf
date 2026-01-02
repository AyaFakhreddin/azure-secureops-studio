data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "secops" {
  name = var.secops_rg_name
}

resource "azurerm_log_analytics_workspace" "accesslens_law" {
  name                = var.accesslens_law_name
  location            = data.azurerm_resource_group.secops.location
  resource_group_name = data.azurerm_resource_group.secops.name

  sku               = "PerGB2018"
  retention_in_days = var.accesslens_law_retention

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_monitor_diagnostic_setting" "subscription_activity_logs" {
  name                       = var.accesslens_diag_name
  target_resource_id         = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.accesslens_law.id

  enabled_log { category = "Administrative" }
  enabled_log { category = "Security" }
  enabled_log { category = "Policy" }
  enabled_log { category = "Alert" }
  enabled_log { category = "ServiceHealth" }
  enabled_log { category = "Recommendation" }
}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "sentinel" {
  workspace_id = azurerm_log_analytics_workspace.accesslens_law.id

  lifecycle {
    prevent_destroy = true
  }
}
